// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";

interface IRewardDistributor {
    function distributeAndUpdateRecipients(
        address[] memory currentRecipients,
        uint256[] memory currentWeights,
        address[] memory newRecipients,
        uint256[] memory newWeights
    ) external;

    function currentRecipientGroup() external view returns (bytes32);
    function currentRecipientWeights() external view returns (bytes32);
}

/// @notice Governance action to be deployed on Nova. Updates all l1 timelock alias recipients in all fee distribution
/// contracts to the nova-to-l1 router address; preserves all other recipients and all weights.
/// Note that the Nova L1 Base fee distributor is not updated since the timelock alias is not a recipient.
contract AIPNovaFeeRoutingAction {
    address public immutable l1GovTimelockAlias = 0xf7951D92B0C345144506576eC13Ecf5103aC905a;
    uint256 public immutable fullWeight = 10_000;

    address public immutable novaL1SurplusFeeDistr = 0x509386DbF5C0BE6fd68Df97A05fdB375136c32De;

    address public immutable novaL2SurplusFeeDistr = 0x3B68a689c929327224dBfCe31C1bf72Ffd2559Ce;

    address public immutable novaL2BaseFeeDistr = 0x9fCB6F75D99029f28F6F4a1d277bae49c5CAC79f;
    uint256 public immutable novaL2BaseWeight0 = 8000;
    uint256 public immutable novaL2BaseWeight1 = 375;
    uint256 public immutable novaL2BaseWeight2 = 373;
    uint256 public immutable novaL2BaseWeight3 = 373;
    uint256 public immutable novaL2BaseWeight4 = 373;
    uint256 public immutable novaL2BaseWeight5 = 373;
    uint256 public immutable novaL2BaseWeight6 = 133;

    // novaL2BaseRecipient0 is the gov timelock alias
    address public immutable novaL2BaseRecipient1 = 0xD0749b3e537Ed52DE4e6a3Ae1eB6fc26059d0895;
    address public immutable novaL2BaseRecipient2 = 0x41C327d5fc9e29680CcD45e5E52446E0DB3DAdFd;
    address public immutable novaL2BaseRecipient3 = 0x02C2599aa929e2509741b44F3a13029745aB1AB2;
    address public immutable novaL2BaseRecipient4 = 0xA221f29236996BDEfA5C585acdD407Ec84D78447;
    address public immutable novaL2BaseRecipient5 = 0x0fB1f1a31429F1A90a19Ab5486a6DFb384179641;
    address public immutable novaL2BaseRecipient6 = 0xb814441ed86e98e8B83d31eEC095e4a5A36Fc3c2;

    address public immutable novaToL1Router = 0x36D0170D92F66e8949eB276C3AC4FEA64f83704d;

    error NotAContract(address addr);

    constructor() {
        // sanity check:
        if (!Address.isContract(novaToL1Router)) {
            revert NotAContract(novaToL1Router);
        }
    }

    function perform() external {
        // upgrade executor should have at least 3 * fullWeight ETH to fund the distributors
        // we need each of the reward distributors to have at least fullWeight in balance
        // otherwise we may get NoFundsToDistribute() errors
        require(address(this).balance >= 3 * fullWeight, "AIPNovaFeeRoutingAction: insufficient balance");
        _fundDistributor(novaL1SurplusFeeDistr);
        _fundDistributor(novaL2SurplusFeeDistr);
        _fundDistributor(novaL2BaseFeeDistr);

        // L1 surplus: replace only recipient (timelock alias) with the router
        address[] memory currentNovaL1SurplusRecipients = new address[](1);
        currentNovaL1SurplusRecipients[0] = l1GovTimelockAlias;

        uint256[] memory currentNovaL1SurplusWeights = new uint256[](1);
        currentNovaL1SurplusWeights[0] = fullWeight;

        address[] memory newL1SurplusRecipients = new address[](1);
        newL1SurplusRecipients[0] = novaToL1Router;

        // preserve current weights, update recipients
        IRewardDistributor(novaL1SurplusFeeDistr).distributeAndUpdateRecipients({
            currentRecipients: currentNovaL1SurplusRecipients,
            currentWeights: currentNovaL1SurplusWeights,
            newRecipients: newL1SurplusRecipients,
            newWeights: currentNovaL1SurplusWeights
        });

        // L2 surplus: replace only recipient (timelock alias) with the router
        address[] memory currentNovaL2SurplusRecipients = new address[](1);
        currentNovaL2SurplusRecipients[0] = l1GovTimelockAlias;

        uint256[] memory novaL2SurplusWeights = new uint256[](1);
        novaL2SurplusWeights[0] = fullWeight;

        address[] memory newL2SurplusRecipients = new address[](1);
        newL2SurplusRecipients[0] = novaToL1Router;

        // preserve current weights, update recipients
        IRewardDistributor(novaL2SurplusFeeDistr).distributeAndUpdateRecipients({
            currentRecipients: currentNovaL2SurplusRecipients,
            currentWeights: novaL2SurplusWeights,
            newRecipients: newL2SurplusRecipients,
            newWeights: novaL2SurplusWeights
        });

        // L2 base: replace first recipient (timelock alias) with router; keep other recipients the same.
        address[] memory currentNovaL2BaseRecipients = new address[](7);
        currentNovaL2BaseRecipients[0] = l1GovTimelockAlias;
        currentNovaL2BaseRecipients[1] = novaL2BaseRecipient1;
        currentNovaL2BaseRecipients[2] = novaL2BaseRecipient2;
        currentNovaL2BaseRecipients[3] = novaL2BaseRecipient3;
        currentNovaL2BaseRecipients[4] = novaL2BaseRecipient4;
        currentNovaL2BaseRecipients[5] = novaL2BaseRecipient5;
        currentNovaL2BaseRecipients[6] = novaL2BaseRecipient6;

        address[] memory newNovaL2BaseRecipients = new address[](7);
        newNovaL2BaseRecipients[0] = novaToL1Router;
        for (uint256 i = 1; i < currentNovaL2BaseRecipients.length; i++) {
            newNovaL2BaseRecipients[i] = currentNovaL2BaseRecipients[i];
        }

        uint256[] memory currentNovaL2BaseWeights = new uint256[](7);
        currentNovaL2BaseWeights[0] = novaL2BaseWeight0;
        currentNovaL2BaseWeights[1] = novaL2BaseWeight1;
        currentNovaL2BaseWeights[2] = novaL2BaseWeight2;
        currentNovaL2BaseWeights[3] = novaL2BaseWeight3;
        currentNovaL2BaseWeights[4] = novaL2BaseWeight4;
        currentNovaL2BaseWeights[5] = novaL2BaseWeight5;
        currentNovaL2BaseWeights[6] = novaL2BaseWeight6;

        // preserve current weights, update recipients
        IRewardDistributor(novaL2BaseFeeDistr).distributeAndUpdateRecipients({
            currentRecipients: currentNovaL2BaseRecipients,
            currentWeights: currentNovaL2BaseWeights,
            newRecipients: newNovaL2BaseRecipients,
            newWeights: currentNovaL2BaseWeights
        });
    }

    function _fundDistributor(address recipient) internal {
        (bool b, ) = recipient.call{value: fullWeight}("");
        require(b, "AIPNovaFeeRoutingAction: funding failed");
    }
}
