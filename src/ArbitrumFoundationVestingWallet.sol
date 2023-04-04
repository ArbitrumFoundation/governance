// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/finance/VestingWalletUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IERC20VotesUpgradeable} from "./Util.sol";

interface IL2ArbitrumGoverner {
    function token() external view returns (IERC20VotesUpgradeable);
    function EXCLUDE_ADDRESS() external view returns (address);
}

/// @notice A wallet that vests tokens over time. Votes are delegated to exclude address. Beneficiary can be updated by owner.
contract ArbotrumFoundationVestingWallet is VestingWalletUpgradeable, OwnableUpgradeable {
    address private _beneficiary;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _beneficiaryAddress,
        uint64 _startTimestamp,
        uint64 _durationSeconds,
        address _arbitrumGoverner,
        address _owner
    ) public initializer {
        // init vesting wallet
        __VestingWallet_init(_beneficiaryAddress, _startTimestamp, _durationSeconds);
        _beneficiary = _beneficiaryAddress;

        // set owner
        __Ownable_init();
        _transferOwnership(_owner);

        // delegate to exclude address
        IL2ArbitrumGoverner arbitrumGoverner = IL2ArbitrumGoverner(_arbitrumGoverner);
        IERC20VotesUpgradeable voteToken = arbitrumGoverner.token();
        address excludeAddress = arbitrumGoverner.EXCLUDE_ADDRESS();
        voteToken.delegate(excludeAddress);
    }

    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary(), "ArbotrumFoundationVestingWallet: not beneficiary");
        _;
    }

    // @dev inheritted OZ  VestingWalletUpgradeable contract has private _beneficiary var. New _beneficiary var is added to this contract and beneficiary() getter is overridden so that setBeneficiary is available.
    function beneficiary() public view override returns (address) {
        return _beneficiary;
    }

    // @notice set new beneficiary; only owner can call
    function setBeneficiary(address _newBeneficiary) public onlyOwner {
        _beneficiary = _newBeneficiary;
    }

    // @notice release vested tokens; only benefiary can call
    function release(address token) public override onlyBeneficiary {
        super.release(token);
    }
}
