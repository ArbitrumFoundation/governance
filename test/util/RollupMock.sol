// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../src/GovernedChainsConfirmationTracker.sol";

contract RollupMock is IRollup {
    mapping(bytes32 => AssertionNode) assertions;

    constructor() {
        AssertionNode memory unconfirmed;
        assertions[keccak256("UNCONFIRMED")] = unconfirmed;

        AssertionNode memory oneHundred;
        oneHundred.createdAtBlock = 100;
        oneHundred.status = AssertionStatus.Confirmed;
        assertions[keccak256("100")] = oneHundred;

        AssertionNode memory twoHundred;
        twoHundred.createdAtBlock = 200;
        twoHundred.status = AssertionStatus.Confirmed;
        assertions[keccak256("200")] = twoHundred;

        AssertionNode memory threeHundred;
        threeHundred.createdAtBlock = 300;
        threeHundred.status = AssertionStatus.Confirmed;
        assertions[keccak256("300")] = threeHundred;

        AssertionNode memory fourHundred;
        fourHundred.createdAtBlock = 400;
        fourHundred.status = AssertionStatus.Confirmed;
        assertions[keccak256("400")] = fourHundred;
    }

    function getAssertion(bytes32 assertionHash) external view returns (AssertionNode memory) {
        return assertions[assertionHash];
    }
}
