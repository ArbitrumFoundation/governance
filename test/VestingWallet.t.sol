// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
// import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/VotingVestingWallet.sol";

import "./util/TestUtil.sol";

import "forge-std/Test.sol";

contract TokenDistributorTest is Test {
    address beneficiaryAddress = address(1);
    uint64 startTimestamp = 100;
    uint64 durationSeconds = 20;
    address distributor = address(2);
    address token = address(3);
    address payable governor = payable(address(4));

    function testDoesDeploy() external {
        VotingVestingWallet wall = new VotingVestingWallet(
            beneficiaryAddress,
            startTimestamp,
            durationSeconds,
            distributor,
            token,
            governor
        );

        assertEq(wall.distributor(), distributor, "Distributor");
        
        assertEq(wall.governor(), governor, "Governor");
    }
}
