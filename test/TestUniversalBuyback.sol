// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Assert } from "truffle/Assert.sol";

import { Env } from "./Env.sol";
import { LibExchange, LibUniversalBuyback } from "./Libs.sol";

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

		address TREASURY = 0x0d1d68C73b57a53B1DdCD287aCf4e66Ed745B759;
		address _exchange = LibExchange.newExchange($.UniswapV2_Compatible_ROUTER02, TREASURY);
		address _buyback = LibUniversalBuyback.newUniversalBuyback($.CAKE, $.WHEAT, $.GRO, TREASURY, _exchange));

		Transfers._pushFunds($.CAKE, _buyback, 20e18);

		uint256 _pendingBefore = UniversalBuyback(_buyback).pendingBuyback();
		Assert.equal(_pendingBefore, 20e18, "CAKE balance before must be 20e18");

		(uint256 _burning1, uint256 _burning2) =  UniversalBuyback(_buyback).pendingBurning();
		UniversalBuyback(_buyback).gulp(_burning1, _burning2);

		uint256 _pendingAfter = UniversalBuyback(_buyback).pendingBuyback();
		Assert.equal(_pendingAfter, 0e18, "CAKE balance after must be 0e18");
	}
}
