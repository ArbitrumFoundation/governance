// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice contract for AIP-1.1 https://forum.arbitrum.foundation/t/proposal-aip-1-1-lockup-budget-transparency/13360.
///  AIP-1.1 Is a non-constitutional proposal as per the constitution and thus is to be put to an on-chain vote; however,
/// it technically requires no on-chain execution. This contract is to be used as its on-chain target as a formality
/// and for bookkeeping.
/// @dev note that this is not a "Gov Action" contract and thus does not conform to that standard.
contract AIP1Point1Target {
    address public immutable treasuryTimelock;
    address public immutable arbitrumFoundationWallet;

    bool public passed = false;

    event AIP1Point1Passed(address arbitrumFoundationWallet);

    constructor(address _treasuryTimelock, address _arbitrumFoundationWallet) {
        treasuryTimelock = _treasuryTimelock;
        arbitrumFoundationWallet = _arbitrumFoundationWallet;
    }

    function effectuate() external {
        require(msg.sender == treasuryTimelock, "AIP1Point1Target: only from treasury timelock");
        require(!passed, "AIP1Point1Target: already passed");
        passed = true;
        emit AIP1Point1Passed(arbitrumFoundationWallet);
    }
}
