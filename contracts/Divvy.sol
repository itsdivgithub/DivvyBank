// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

contract Divvy is ERC721URIStorage, KeeperCompatibleInterface {
    // Variables

    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    struct Loan {
        address buyer;
        uint256 loanStart;
        uint256 loanAmount;
        uint256 repayAmount;
        uint256 remainingAmount;
        uint256 tenure;
        uint256 payoutPerMonth;
        uint256 penalty;
        uint256 intervalTimes;
        uint256 NFTId;
        bool completed;
    }

    address[] public borrowers;

    mapping(address => Loan) public addressToLoan;

    address payable public seller;
    uint public id;
    // uint public intervalTimes;
    // uint public immutable interval = (30 days);
    uint public immutable interval;
    uint public lastTimeStamp;

    event initEvent(
        address _buyer,
        uint _loanAmount,
        uint _tenure,
        uint startTime
    );
    event NFTReceivedEvent(uint _id);
    event FullPaidEvent(address _buyer, uint _installment);
    event SettleLoan(address _buyer, bool completed);

    constructor(address payable _seller) ERC721("Property", "PTY") {
        seller = _seller;
        // lastTimeStamp = block.timestamp;

        interval = 2592000; // 30 days in sec
        // interval = 10;
        lastTimeStamp = block.timestamp;
    }

    function createToken(string memory tokenURI) public payable returns (uint) {
        // Incrementing the total tokenIds
        _tokenIds.increment();

        // Value of the recent tokenId (NFT_ID)
        uint256 newTokenId = _tokenIds.current();

        // Create or mint the UNIQUE token (NFT) with the tokenId (NFT_ID) for the SENDER
        _mint(address(this), newTokenId);

        // Create a unique identifier for the token (NFT) created
        _setTokenURI(newTokenId, tokenURI);
        id = newTokenId;
        return newTokenId;
    }

    function getId() public view returns (uint) {
        return id;
    }

    function init(
        address _buyer,
        uint _loanAmount,
        uint _tenure,
        uint tokenId
    ) public {
        bool accountExists = false;

        for (uint i = 0; i < borrowers.length; i++) {
            if (borrowers[i] == msg.sender) {
                accountExists = true;
            }
        }

        require(
            (addressToLoan[msg.sender].completed == true) ||
                accountExists == false,
            "You already have a running loan."
        );

        uint256 repayAmount = _loanAmount + (_loanAmount / 5);
        uint256 remainingAmount = repayAmount;
        uint256 penalty = (repayAmount / 10);
        uint256 payoutPerMonth = repayAmount / _tenure;

        borrowers.push(msg.sender);

        addressToLoan[msg.sender] = Loan(
            _buyer,
            block.timestamp,
            _loanAmount * (1 ether),
            repayAmount * (1 ether),
            remainingAmount * (1 ether),
            _tenure * (30 days),
            payoutPerMonth * (1 ether),
            penalty * (1 ether),
            _tenure,
            tokenId,
            false
        );

        emit NFTReceivedEvent(tokenId);
        emit initEvent(_buyer, _loanAmount, _tenure, block.timestamp);
    }

    // Pay the due amount (periodically)
    function pay() public payable {
        Loan storage present = addressToLoan[msg.sender];
        require(
            msg.value == present.payoutPerMonth,
            "Amount not accurate. Try again!"
        );

        if (present.intervalTimes == 0 && present.repayAmount == 0)
            present.completed = true;

        // require(currState == State.AWAITING_RELOAN, "Reloan not started yet or you already paid");
        require(present.completed == false, "Amount already paid");

        // Pay periodically

        present.repayAmount -= msg.value;
        present.intervalTimes--;

        //seller.transfer(msg.value);
        (bool res, bytes memory data) = seller.call{value: msg.value}("");

        require(res, "Transfer failed");
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        if ((block.timestamp - lastTimeStamp) > interval) {
            lastTimeStamp = block.timestamp;

            pay();
        }
    }

    function payInFull() public payable {
        Loan storage present = addressToLoan[msg.sender];

        require(present.completed == false, "Amount already paid");
        require(
            msg.value == present.repayAmount + present.penalty,
            "The repay amount is not enough"
        ); // 10% Penalty for late reloan

        present.repayAmount = 0;
        present.intervalTimes = 0;

        present.completed = true;

        (bool res, bytes memory data) = seller.call{value: msg.value}("");

        require(res, "Transfer failed");

        emit FullPaidEvent(msg.sender, msg.value);
    }

    function fullPaymentWithPenalty() public view returns (uint) {
        return
            addressToLoan[msg.sender].repayAmount +
            addressToLoan[msg.sender].penalty;
    }

    function settleLoan() public {
        Loan storage present = addressToLoan[msg.sender];

        require(
            (present.loanStart + block.timestamp + 1 weeks) > present.tenure,
            "Time still remaining for settlement"
        );

        if (!present.completed) {
            //transfer NFT ownership to seller
            _transfer(address(this), seller, present.NFTId);
        }

        if (present.completed) {
            //transfer NFT ownership to buyer
            _transfer(address(this), present.buyer, present.NFTId);
        }

        present.completed = true;

        emit SettleLoan(msg.sender, true);
    }

    // function accBalance() external view returns (uint) {
    //     return address(this).balance;
    // }

    function loanAmt() external view returns (uint) {
        return addressToLoan[msg.sender].loanAmount;
    }

    function installmentAmt() external view returns (uint) {
        return addressToLoan[msg.sender].payoutPerMonth;
    }

    function repayAmt() external view returns (uint) {
        return addressToLoan[msg.sender].repayAmount;
    }

    function tenure() external view returns (uint) {
        return addressToLoan[msg.sender].intervalTimes;
    }

    function success() external view returns (bool) {
        return addressToLoan[msg.sender].completed;
    }

    function buyerAddress() external view returns (address) {
        return addressToLoan[msg.sender].buyer;
    }

    function loanStartedOn() external view returns (uint) {
        return addressToLoan[msg.sender].loanStart;
    }
}
