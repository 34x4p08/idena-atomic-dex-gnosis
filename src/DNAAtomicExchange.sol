// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

contract DNAAtomicExchange {
    struct MatchedOrder {
        bool confirmed;
        address owner;
        address payoutAddress;
        address matcher;
        uint amountXDAI;
        uint matchDeadline;
        uint executionDeadline;
    }

    address public owner;
    uint public ownerClaimPeriod;
    uint public minOrderTTL;
    uint public securityDepositAmount;
    uint public protocolPenaltyFee;
    address public protocolFund;

    mapping (bytes32 => MatchedOrder) public orders;
    mapping (address => uint) public securityDeposits;
    mapping (address => bool) public securityDepositInUse;

    event OrderConfirmed(bytes32 indexed secretHash, uint amountXDAI, address payoutAddress, uint deadline);
    event OrderMatched(bytes32 indexed secretHash, address matcher);
    event OrderCompleted(bytes32 indexed secretHash, bytes secret);
    event OwnerPenalized(bytes32 indexed secretHash);
    event OrderBurned(bytes32 indexed secretHash);

    event SecurityDepositSubmitted(address indexed account);
    event SecurityDepositWithdrawn(address indexed account);

    constructor(uint _ownerClaimPeriod, uint _securityDepositAmount, uint _minOrderTTL, uint _protocolPenaltyFee, address _protocolFund) {
        require(_protocolPenaltyFee <= 1e18, "too much");
        owner = msg.sender;
        ownerClaimPeriod = _ownerClaimPeriod;
        securityDepositAmount = _securityDepositAmount;
        minOrderTTL = _minOrderTTL;
        protocolPenaltyFee = _protocolPenaltyFee;
        protocolFund = _protocolFund;
    }

    // owner-side
    function confirmOrder(bytes32 secretHash, uint amountXDAI, address payoutAddress, uint deadline) external {
        require(deadline >= block.timestamp + minOrderTTL, "cannot confirm: not enough time");
        require(payoutAddress != address(0), "cannot confirm: zero payout address");
        require(amountXDAI != 0, "cannot confirm: amountXDAI == zero");

        require(!orders[secretHash].confirmed, "cannot confirm: already confirmed");

        require(securityDeposits[msg.sender] == securityDepositAmount, "cannot confirm: not enough security deposit");
        require(!securityDepositInUse[msg.sender], "cannot confirm: security deposit in use");

        securityDepositInUse[msg.sender] = true;
        orders[secretHash].confirmed = true;
        orders[secretHash].matchDeadline = deadline;
        orders[secretHash].amountXDAI = amountXDAI;
        orders[secretHash].payoutAddress = payoutAddress;
        orders[secretHash].owner = msg.sender;

        emit OrderConfirmed(secretHash, amountXDAI, payoutAddress, deadline);
    }

    function matchOrder(bytes32 secretHash) payable external {
        require(orders[secretHash].confirmed, "cannot match: order isn't confirmed");
        require(msg.value == orders[secretHash].amountXDAI, "cannot match: incorrect amount");
        require(orders[secretHash].matchDeadline > block.timestamp, "cannot match: order expired");
        require(orders[secretHash].executionDeadline == 0, "cannot match: order already matched");

        orders[secretHash].executionDeadline = block.timestamp + ownerClaimPeriod;
        orders[secretHash].matcher = msg.sender;

        emit OrderMatched(secretHash, msg.sender);
    }

    function penalizeOwner(bytes32 secretHash) external {
        require(orders[secretHash].executionDeadline != 0, "cannot penalize: order isn't matched");
        require(block.timestamp >= orders[secretHash].executionDeadline, "cannot penalize: execution in progress");

        address orderOwner = orders[secretHash].owner;
        uint securityDeposit = securityDeposits[orderOwner];
        address matcher = orders[secretHash].matcher;
        uint amountXDAI = orders[secretHash].amountXDAI;

        delete orders[secretHash];
        securityDeposits[orderOwner] = 0;
        securityDepositInUse[orderOwner] = false;

        payable(matcher).transfer(amountXDAI);

        uint protocolShare = securityDeposit * protocolPenaltyFee / 1e18;

        payable(protocolFund).transfer(protocolShare);
        payable(matcher).transfer(securityDeposit - protocolShare);

        emit OwnerPenalized(secretHash);
    }

    function burnOrder(bytes32 secretHash) external {
        require(orders[secretHash].executionDeadline == 0, "cannot burn: order has been matched");
        require(orders[secretHash].confirmed, "cannot burn: order doesn't exist");
        require(block.timestamp >= orders[secretHash].matchDeadline, "cannot burn: deadline not reached");

        address orderOwner = orders[secretHash].owner;

        delete orders[secretHash];
        securityDepositInUse[orderOwner] = false;

        emit OrderBurned(secretHash);
    }

    // owner-side
    function completeOrder(bytes calldata secret) external {
        bytes32 secretHash = keccak256(secret);

        require(orders[secretHash].executionDeadline > block.timestamp, "cannot match: order expired");

        uint amountXDAI = orders[secretHash].amountXDAI;
        address payoutAddress = orders[secretHash].payoutAddress;
        address orderOwner = orders[secretHash].owner;

        delete orders[secretHash];
        securityDepositInUse[orderOwner] = false;

        payable(payoutAddress).transfer(amountXDAI);

        emit OrderCompleted(secretHash, secret);
    }

    function submitSecurityDeposit() payable external {
        require(securityDeposits[msg.sender] == 0, "cannot submit security deposit: already exists");
        require(msg.value == securityDepositAmount, "cannot submit security deposit: incorrect value");

        securityDeposits[msg.sender] = securityDepositAmount;

        emit SecurityDepositSubmitted(msg.sender);
    }

    function withdrawSecurityDeposit() external {
        uint securityDeposit = securityDeposits[msg.sender];
        require(securityDeposit != 0, "cannot withdraw security deposit: doesn't exist");

        require(!securityDepositInUse[msg.sender], "cannot withdraw security deposit: in use");

        securityDeposits[msg.sender] = 0;

        payable(msg.sender).transfer(securityDeposit);

        emit SecurityDepositWithdrawn(msg.sender);
    }
}