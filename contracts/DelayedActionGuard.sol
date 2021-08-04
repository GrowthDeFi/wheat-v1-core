// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract DelayedActionGuard is Ownable
{
	uint64 constant DEFAULT_WAIT_INTERVAL = 1 days;
	uint64 constant DEFAULT_OPEN_INTERVAL = 1 days;

	struct Interval {
		bytes32 hash;
		uint256 start;
		uint256 end;
	}

	mapping(bytes4 => Interval) private intervals;

	modifier delayed(bytes4 _selector, bytes32 _hash)
	{
		Interval storage interval = intervals[_selector];
		require(interval.hash == _hash, "invalid action");
		require(interval.start <= now && now < interval.end, "unavailable action");
		interval.hash = 0;
		interval.start = 0;
		interval.end = 0;
		emit ExecuteDelayedAction(_selector, _hash);
		_;
	}

	function announceDelayedAction(bytes4 _selector, bytes memory _params) external onlyOwner
	{
		(uint64 _wait, uint64 _open) = _defaultIntervalParams();
		Interval storage interval = intervals[_selector];
		require(interval.end == 0, "ongoing action");
		interval.hash = keccak256(_params);
		interval.start = now + _wait;
		interval.end = interval.start + _open;
		emit AnnounceDelayedAction(_selector, interval.hash);
	}

	/*
	function cancelDelayedAction(bytes4 _selector) external onlyOwner
	{
		Interval storage interval = intervals[_selector];
		require(interval.end != 0, "invalid action");
		emit CancelDelayedAction(_selector, interval.hash);
		interval.hash = 0;
		interval.start = 0;
		interval.end = 0;
	}
	*/

	function _defaultIntervalParams() internal pure virtual returns (uint64 _wait, uint64 _open)
	{
		return (DEFAULT_WAIT_INTERVAL, DEFAULT_OPEN_INTERVAL);
	}

	event AnnounceDelayedAction(bytes4 _selector, bytes32 _hash);
	event ExecuteDelayedAction(bytes4 _selector, bytes32 _hash);
	// event CancelDelayedAction(bytes4 _selector, bytes32 _hash);
}
