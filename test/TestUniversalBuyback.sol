// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert } from "truffle/Assert.sol";

import { Env } from "./Env.sol";

import { UniversalBuyback } from "../contracts/UniversalBuyback.sol";

import { Transfers } from "../contracts/modules/Transfers.sol";

import { $ } from "../contracts/network/$.sol";

contract TestUniversalBuyback is Env
{
	function test01() external
	{
		_burnAll($.CAKE);
		_burnAll($.WHEAT);
		_burnAll($.GRO);

		_mint($.CAKE, 20e18); // 20 CAKE

		address _buyback = CAKE_BUYBACK;

		Transfers._pushFunds($.CAKE, _buyback, 20e18);

		uint256 _pendingBefore = UniversalBuyback(_buyback).pendingBuyback();
		Assert.equal(_pendingBefore, 20e18, "CAKE balance before must be 20e18");

		UniversalBuyback(_buyback).gulp();

		uint256 _pendingAfter = UniversalBuyback(_buyback).pendingBuyback();
		Assert.equal(_pendingAfter, 0e18, "CAKE balance after must be 0e18");
	}
}
