// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/DNAAtomicExchange.sol";

contract DeployScript is Script {

    function setUp() public {}

    function run() public {
        address _protocolFund = 0x5E1CF775EC18167722589520b385AfdbF8a4AA5F;

        uint _minOrderTTL = 3 hours;
        uint _ownerClaimPeriod = 0.5 hours;
        uint _securityDepositAmount = 10 ether;
        uint _protocolPenaltyFee = 0.5e18;

        uint key = vm.envUint("PRIVATE_KEY");
        vm.broadcast(key);

        new DNAAtomicExchange(_ownerClaimPeriod, _securityDepositAmount, _minOrderTTL, _protocolPenaltyFee, _protocolFund);
    }
}
