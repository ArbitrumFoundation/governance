// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/finance/VestingWalletUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20VotesUpgradeable} from "./Util.sol";

interface IL2ArbitrumGoverner {
    function token() external view returns (IERC20VotesUpgradeable);
    function EXCLUDE_ADDRESS() external view returns (address);
}

/**
 * @notice A wallet for foundation owned founds as per AIP-1.1 specification.
 * DAO can migrate funds to new wallet.
 * Wallet vests funds over time on a linear schedule.
 * Governance votes are delegated to exclude address.
 * Beneficiary can be updated by DAO.
 */

contract ArbitrumFoundationVestingWallet is VestingWalletUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address private _beneficiary;

    event NewBeneficiary(address newBeneficiary);
    event TokenMigrated(address token, uint256 amount, address destination);
    event EthMigrated(uint256 amount, address destination);

    constructor() {
        _disableInitializers();
    }
    /// @param _beneficiaryAddress Can release funds and receives released funds
    /// @param _startTimestamp The time to start vesting
    /// @param _durationSeconds The time period for funds to fully vest
    /// @param _arbitrumGoverner Core DAO Governer address
    /// @param _owner Arbitrum DAO. Can migrate funds to new wallet and change beneficiary

    function initialize(
        address _beneficiaryAddress,
        uint64 _startTimestamp,
        uint64 _durationSeconds,
        address _arbitrumGoverner,
        address _owner
    ) public initializer {
        require(
            _beneficiaryAddress != address(0),
            "ArbitrumFoundationVestingWallet: zero beneficiary address"
        );
        require(
            _arbitrumGoverner != address(0),
            "ArbitrumFoundationVestingWallet: zero arbitrumGoverner address"
        );

        // init vesting wallet
        // first argument (beneficiary) is unused by contract; a dummy value is provided
        __VestingWallet_init(address(1), _startTimestamp, _durationSeconds);
        _beneficiary = _beneficiaryAddress;

        // set owner (DAO)
        __Ownable_init();
        _transferOwnership(_owner);

        // delegate to exclude address
        IL2ArbitrumGoverner arbitrumGoverner = IL2ArbitrumGoverner(_arbitrumGoverner);
        IERC20VotesUpgradeable voteToken = arbitrumGoverner.token();
        address excludeAddress = arbitrumGoverner.EXCLUDE_ADDRESS();
        voteToken.delegate(excludeAddress);
    }

    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary(), "ArbitrumFoundationVestingWallet: not beneficiary");
        _;
    }

    // @dev inheritted OZ  VestingWalletUpgradeable contract has private _beneficiary var. New _beneficiary var is added to this contract and beneficiary() getter is overridden so that setBeneficiary is available.
    function beneficiary() public view override returns (address) {
        return _beneficiary;
    }

    /// @notice set new beneficiary; only the owner (Arbitrum DAO) can call
    /// @param _newBeneficiary new contract to receive proceeds from the vesting contract
    /// Emits event NewBeneficiary
    function setBeneficiary(address _newBeneficiary) public onlyOwner {
        _beneficiary = _newBeneficiary;
        emit NewBeneficiary(_newBeneficiary);
    }

    /// @notice release vested tokens; only beneficiary can call
    /// @param _token Address of token to release
    function release(address _token) public override onlyBeneficiary {
        super.release(_token);
    }

    // @notice eth sent to wallet is automatically put under vesting schedule; only benefitiary can release
    function release() public override onlyBeneficiary {
        super.release();
    }

    /// @notice DAO can migrate unvested (as well as vested but not yet claimed) tokens to a new wallet, e.g. one with a different vesting schedule, as per AIP-1.1.
    /// @param _token address of token to be migrated
    /// @param _wallet address of wallet to receive tokens
    /// Emits event TokenMigrated
    function migrateTokensToNewWallet(address _token, address _wallet) public onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeTransfer(_wallet, tokenBalance);
        emit TokenMigrated(_token, tokenBalance, _wallet);
    }

    /// @notice DAO can migrate unvested (as well as vested but not yet claimed) Eth to a new wallet, e.g. one with a different vesting schedule, as per AIP-1.1.
    /// @param _wallet address of wallet to receive Eth
    /// Emits event EthMigrated
    function migrateEthToNewWallet(address _wallet) public onlyOwner {
        uint256 ethBalance = address(this).balance;
        _wallet.call{value: ethBalance}("");
        emit EthMigrated(ethBalance, _wallet);
    }
}
