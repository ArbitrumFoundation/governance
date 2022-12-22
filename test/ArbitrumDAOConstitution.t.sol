// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "../src/ArbitrumDAOConstitution.sol";

import "forge-std/Test.sol";

contract ArbitrumDAOConstitutionTest is Test {
    bytes32 initialHash = bytes32("0x123");
    address owner = address(12_345);

    function deployConstition() internal returns (ArbitrumDAOConstitution) {
        vm.prank(owner);
        ArbitrumDAOConstitution arbitrumDAOConstitution = new ArbitrumDAOConstitution(
                initialHash
            );
        return arbitrumDAOConstitution;
    }

    function testConstructor() external {
        ArbitrumDAOConstitution arbitrumDAOConstitution = new ArbitrumDAOConstitution(
                initialHash
            );
        bytes32 storedHash = arbitrumDAOConstitution.constitutionHash();
        assertEq(storedHash, initialHash, "initiation hash set");
    }

    function testOwnerCanSetHash() external {
        ArbitrumDAOConstitution arbitrumDAOConstitution = new ArbitrumDAOConstitution(
                initialHash
            );
        bytes32 newHash = bytes32("0x12345");
        arbitrumDAOConstitution.setConstitutionHash(newHash);
        bytes32 newStoredHash = arbitrumDAOConstitution.constitutionHash();
        assertEq(newHash, newStoredHash, "new hash set");
    }

    function testOwnerCanSetHashTwice() external {
        ArbitrumDAOConstitution arbitrumDAOConstitution = new ArbitrumDAOConstitution(
                initialHash
            );
        bytes32 newHash = bytes32("0x12345");
        arbitrumDAOConstitution.setConstitutionHash(newHash);
        bytes32 newStoredHash = arbitrumDAOConstitution.constitutionHash();
        assertEq(newHash, newStoredHash, "new hash set");

        bytes32 newNewHash = bytes32("0x12345789");
        arbitrumDAOConstitution.setConstitutionHash(newNewHash);
        bytes32 newNewStoredHash = arbitrumDAOConstitution.constitutionHash();
        assertEq(newNewStoredHash, newNewHash, "new new hash set");
    }

    function testMonOwnerCannotSetHash() external {
        ArbitrumDAOConstitution arbitrumDAOConstitution = new ArbitrumDAOConstitution(
                initialHash
            );
        address someRando = address(987_654_321);
        vm.startPrank(someRando);
        vm.expectRevert("Ownable: caller is not the owner");
        arbitrumDAOConstitution.setConstitutionHash("0x111");
        vm.stopPrank();
    }
}
