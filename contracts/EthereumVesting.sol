pragma solidity ^0.5.0;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/**
 * @title EthereumVesting
 * @dev A contract that can release its ethereum balance gradually like a
 * typical vesting scheme, with a cliff and vesting period. Optionally revocable by the
 * owner.
 */
contract EthereumVesting is Ownable {
    // The vesting schedule is time-based (i.e. using block timestamps as opposed to e.g. block numbers), and is
    // therefore sensitive to timestamp manipulation (which is something miners can do, to a certain degree). Therefore,
    // it is recommended to avoid using short time durations (less than a minute). Typical vesting schemes, with a
    // cliff period of a year and a duration of four years, are safe to use.
    // solhint-disable not-rely-on-time

    using SafeMath for uint256;

    event EthereumDeposited(uint256 amount);
    event EthereumReleased(uint256 amount);
    event EthereumVestingRevoked();

    // beneficiary of ethereum after they are released
    address payable private _beneficiary;

    // Durations and timestamps are expressed in UNIX time, the same units as block.timestamp.
    uint256 private _cliff;
    uint256 private _start;
    uint256 private _duration;

    bool private _revocable;

    uint256 private _released;
    bool private _revoked;

    /**
     * @dev Creates a vesting contract that vests its balance of Ethereum to the
     * beneficiary, gradually in a linear fashion until start + duration. By then all
     * of the balance will have vested.
     * @param beneficiary address of the beneficiary to whom vested eth are transferred
     * @param cliffDuration duration in seconds of the cliff in which eth will begin to vest
     * @param start the time (as Unix time) at which point vesting starts
     * @param duration duration in seconds of the period in which the eth will vest
     * @param revocable whether the vesting is revocable or not
     */
    constructor (address payable beneficiary, uint256 start, uint256 cliffDuration, uint256 duration, bool revocable) public {
        require(beneficiary != address(0), "EthereumVesting: beneficiary is the zero address");
        // solhint-disable-next-line max-line-length
        require(cliffDuration <= duration, "EthereumVesting: cliff is longer than duration");
        require(duration > 0, "EthereumVesting: duration is 0");
        // solhint-disable-next-line max-line-length
        require(start.add(duration) > block.timestamp, "EthereumVesting: final time is before current time");

        _beneficiary = beneficiary;
        _revocable = revocable;
        _duration = duration;
        _cliff = start.add(cliffDuration);
        _start = start;
    }

    /**
     * Payable fallback function allows ethereum to be deposited into the contract.
     */
    function () payable external {
        emit EthereumDeposited(msg.value);
    }

    /**
     * @return the beneficiary of the ethereum.
     */
    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @return the cliff time of the ethereum vesting.
     */
    function cliff() public view returns (uint256) {
        return _cliff;
    }

    /**
     * @return the start time of the ethereum vesting.
     */
    function start() public view returns (uint256) {
        return _start;
    }

    /**
     * @return the duration of the ethereum vesting.
     */
    function duration() public view returns (uint256) {
        return _duration;
    }

    /**
     * @return true if the vesting is revocable.
     */
    function revocable() public view returns (bool) {
        return _revocable;
    }

    /**
     * @return the amount of the ethereum released.
     */
    function released() public view returns (uint256) {
        return _released;
    }

    /**
     * @return true if the ethereum is revoked.
     */
    function revoked() public view returns (bool) {
        return _revoked;
    }

    /**
     * @notice Transfers vested ethereum to beneficiary.
     */
    function release() public {
        uint256 unreleased = _releasableAmount();

        require(unreleased > 0, "EthereumVesting: no ethereum are due");

        _released = _released.add(unreleased);

        _beneficiary.transfer(unreleased);

        emit EthereumReleased(unreleased);
    }

    /**
     * @notice Allows the owner to revoke the vesting. Ethereum already vested
     * remain in the contract, the rest are returned to the owner.
     */
    function revoke() public onlyOwner {
        require(_revocable, "EthereumVesting: cannot revoke");
        require(!_revoked, "EthereumVesting: eth already revoked");

        uint256 balance = address(this).balance;

        uint256 unreleased = _releasableAmount();
        uint256 refund = balance.sub(unreleased);

        _revoked = true;

        address(uint160(owner())).transfer(refund);

        emit EthereumVestingRevoked();
    }

    /**
     * @dev Calculates the amount that has already vested but hasn't been released yet.
     */
    function _releasableAmount() private view returns (uint256) {
        return _vestedAmount().sub(_released);
    }

    /**
     * @dev Calculates the amount that has already vested.
     */
    function _vestedAmount() private view returns (uint256) {
        uint256 currentBalance = address(this).balance;
        uint256 totalBalance = currentBalance.add(_released);

        if (block.timestamp < _cliff) {
            return 0;
        } else if (block.timestamp >= _start.add(_duration) || _revoked) {
            return totalBalance;
        } else {
            return totalBalance.mul(block.timestamp.sub(_start)).div(_duration);
        }
    }
}
