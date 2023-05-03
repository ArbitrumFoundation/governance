// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/finance/VestingWalletUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IL2ArbitrumGovernor.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @notice A wallet for foundation owned founds as per AIP-1.1 specification.
 * DAO can migrate funds to new wallet.
 * Wallet vests funds over time on a linear schedule.
 * Governance votes are delegated to exclude address.
 * Beneficiary can be updated by DAO.
 */
contract ArbitrumFoundationVestingWallet is VestingWalletUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // a _beneficiary var is declared in VestingWalletUpgradeable; it  is (re)declared here so that setBeneficiary can be used
    address private _beneficiary;

    /**
     * @notice emitted when beneficiary address is changed
     * @param newBeneficiary address of new beneficiary
     * @param caller address that called beneficiary-setter; either current beneficiary or owner (DAO)
     */
    event BeneficiarySet(address indexed newBeneficiary, address indexed caller);

    /**
     * @notice emitted when tokens are migrated to a new wallet
     * @param token address of token being migrated
     * @param destination new wallet address
     * @param amount amount of tokens migrated
     */
    event TokenMigrated(address indexed token, address indexed destination, uint256 amount);

    /**
     * @notice emitted when Eth us migrated to a new wallet
     * @param destination new wallet address
     * @param amount amount of Eth migrated
     */
    event EthMigrated(address indexed destination, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    /**
     * @param _beneficiaryAddress Can release funds and receives released funds
     * @param _startTimestamp The time to start vesting
     * @param _durationSeconds The time period for funds to fully vest
     * @param _arbitrumGoverner Core DAO Governer address
     */
    function initialize(
        address _beneficiaryAddress,
        uint64 _startTimestamp,
        uint64 _durationSeconds,
        address _arbitrumGoverner
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
        __VestingWallet_init(address(0xdead), _startTimestamp, _durationSeconds);
        _setBeneficiary(_beneficiaryAddress);

        // set owner to same order as Governer, i.e., the DAO
        IL2ArbitrumGoverner arbitrumGoverner = IL2ArbitrumGoverner(_arbitrumGoverner);
        address _owner = arbitrumGoverner.owner();
        __Ownable_init();
        _transferOwnership(_owner);

        // delegate to exclude address
        IL2ArbitrumToken voteToken = arbitrumGoverner.token();
        address excludeAddress = arbitrumGoverner.EXCLUDE_ADDRESS();
        voteToken.delegate(excludeAddress);
    }

    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary(), "ArbitrumFoundationVestingWallet: not beneficiary");
        _;
    }

    modifier onlyBeneficiaryOrOwner() {
        require(
            msg.sender == beneficiary() || msg.sender == owner(),
            "ArbitrumFoundationVestingWallet: caller is not beneficiary or owner"
        );
        _;
    }

    /// @dev inheritted OZ VestingWalletUpgradeable contract has private `_beneficiary` variable with no setter. This version can be dynamically updated through the `setBeneficiary` function
    function beneficiary() public view override returns (address) {
        return _beneficiary;
    }

    /// @notice set new beneficiary; only the owner (Arbitrum DAO) or current beneficiary can call
    /// @param _newBeneficiary new contract to receive proceeds from the vesting contract
    /// Emits event BeneficiarySet
    function setBeneficiary(address _newBeneficiary) public onlyBeneficiaryOrOwner {
        _setBeneficiary(_newBeneficiary);
    }

    function _setBeneficiary(address _newBeneficiary) internal {
        _beneficiary = _newBeneficiary;
        emit BeneficiarySet(_newBeneficiary, msg.sender);
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
        require(
            Address.isContract(_wallet),
            "ArbitrumFoundationVestingWallet: new wallet must be a contract"
        );
        IERC20 token = IERC20(_token);
        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeTransfer(_wallet, tokenBalance);
        emit TokenMigrated(_token, _wallet, tokenBalance);
    }

    /// @notice DAO can migrate unvested (as well as vested but not yet claimed) Eth to a new wallet, e.g. one with a different vesting schedule, as per AIP-1.1.
    /// @param _wallet address of wallet to receive Eth
    /// Emits event EthMigrated
    function migrateEthToNewWallet(address _wallet) public onlyOwner {
        require(
            Address.isContract(_wallet),
            "ArbitrumFoundationVestingWallet: new wallet must be a contract"
        );
        uint256 ethBalance = address(this).balance;
        (bool success,) = _wallet.call{value: ethBalance}("");
        require(success, "ArbitrumFoundationVestingWallet: eth transfer failed");
        emit EthMigrated(_wallet, ethBalance);
    }
}
