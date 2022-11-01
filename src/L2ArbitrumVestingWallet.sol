import "@openzeppelin/contracts/finance/VestingWallet.sol";
import "./TokenDistributor.sol";
import {IERC20VotesUpgradeable} from "./Util.sol";
import "./L2ArbitrumGovernor.sol";

contract L2ArbitrumVestingWallet is VestingWallet {
    address public immutable distributor;
    address public immutable token;
    address payable public immutable governer;

    constructor(
        address _beneficiaryAddress,
        uint64 _startTimestamp,
        uint64 _durationSeconds,
        address _distributor,
        address _token,
        address payable _governer
    ) VestingWallet(_beneficiaryAddress, _startTimestamp, _durationSeconds) {
        distributor = _distributor;
        token = _token;
        governer = _governer;
    }

    /// @notice delegate votes to target address
    function delegate(address delegatee) public {
        IERC20VotesUpgradeable(token).delegate(delegatee);
    }

    /// @notice claim tokens from distributor contract
    function claim() public {
        TokenDistributor(distributor).claim();
    }

    /// @notice cast vote in governance proposal
    function castVote(uint256 proposalId, uint8 support) public {
        L2ArbitrumGovernor(governer).castVote(proposalId, support);
    }
}
