// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/DNAAtomicExchange.sol";

contract DNAAtomicExchangeTest is Test {
    DNAAtomicExchange public exchange;

    string rpcUrl = vm.envString("GNOSIS_RPC_URL");

    function setUp() public {
        uint fork = vm.createFork(rpcUrl);
        vm.selectFork(fork);

        vm.rollFork(26959341);

        uint _minOrderTTL = 3 hours;
        uint _ownerClaimPeriod = 0.5 hours;
        uint _securityDepositAmount = 10 ether;
        uint _protocolPenaltyFee = 0.5e18;
        address _protocolFund = makeAddr("protocol");

        exchange = new DNAAtomicExchange(_ownerClaimPeriod, _securityDepositAmount, _minOrderTTL, _protocolPenaltyFee, _protocolFund);
    }

    function testDeploy() public {
        assertEq(exchange.minOrderTTL(), 3 hours);
    }


    event OrderConfirmed(bytes32 indexed secretHash, uint amountXDAI, address payoutAddress, uint deadline);
    event OrderMatched(bytes32 indexed secretHash, address matcher);
    event OrderCompleted(bytes32 indexed secretHash, bytes secret);
    event OwnerPenalized(bytes32 indexed secretHash);
    event OrderBurned(bytes32 indexed secretHash);
    event SecurityDepositSubmitted(address indexed account);
    event SecurityDepositWithdrawn(address indexed account);

    function testComplex(bytes calldata secret) public {
        address alice = makeAddr("alice");
        address alice2 = makeAddr("alice2");
        deal(alice, 10_000 ether);
        vm.startPrank(alice);

        bytes32 secretHash = keccak256(secret);

        vm.expectRevert("cannot withdraw security deposit: doesn't exist");
        exchange.withdrawSecurityDeposit();

        vm.expectRevert("cannot confirm: not enough security deposit");
        exchange.confirmOrder(secretHash, 10 ether, alice2, block.timestamp + 4 hours);

        uint securityDepositAmount = exchange.securityDepositAmount();

        // security deposit
        vm.expectEmit(true, false, false, false);
        emit SecurityDepositSubmitted(alice);
        exchange.submitSecurityDeposit{value: securityDepositAmount}();

        vm.expectRevert("cannot submit security deposit: already exists");
        exchange.submitSecurityDeposit{value: securityDepositAmount}();

        // confirm order
        vm.expectEmit(true, false, false, true);
        emit OrderConfirmed(secretHash, 10 ether, alice2, block.timestamp + 4 hours);
        exchange.confirmOrder(secretHash, 10 ether, alice2, block.timestamp + 4 hours);

        vm.expectRevert("cannot confirm: already confirmed");
        exchange.confirmOrder(secretHash, 10 ether, alice2, block.timestamp + 4 hours);

        vm.expectRevert("cannot withdraw security deposit: in use");
        exchange.withdrawSecurityDeposit();

        address bob = makeAddr("bob");
        deal(bob, 10_000 ether);
        vm.stopPrank();
        vm.startPrank(bob);

        vm.expectRevert("cannot match: incorrect amount");
        exchange.matchOrder{value: 9 ether}(secretHash);

        vm.expectRevert("cannot match: incorrect amount");
        exchange.matchOrder{value: 11 ether}(secretHash);

        uint exchangeBalanceBefore = address(exchange).balance;

        vm.expectEmit(true, false, false, true);
        emit OrderMatched(secretHash, bob);

        exchange.matchOrder{value: 10 ether}(secretHash);
        assertEq(address(exchange).balance - exchangeBalanceBefore, 10 ether);

        vm.expectRevert("cannot match: order already matched");
        exchange.matchOrder{value: 10 ether}(secretHash);

        vm.expectRevert("cannot match: order already matched");
        exchange.matchOrder{value: 10 ether}(secretHash);

        vm.expectRevert("cannot penalize: execution in progress");
        exchange.penalizeOwner(secretHash);

        vm.expectRevert("cannot burn: order has been matched");
        exchange.burnOrder(secretHash);

        vm.stopPrank();
        vm.startPrank(alice);

        // complete
        uint balanceBefore = alice2.balance;
        vm.expectEmit(true, false, false, true);
        emit OrderCompleted(secretHash, secret);
        exchange.completeOrder(secret);

        uint balanceAfter = alice2.balance;
        assertEq(balanceAfter - balanceBefore, 10 ether);

        // security deposit withdraw
        exchange.withdrawSecurityDeposit();
    }
}
