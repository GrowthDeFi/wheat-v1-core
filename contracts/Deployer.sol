// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { CustomMasterChef } from "./CustomMasterChef.sol";
import { WHEAT, stkWHEAT } from "./Tokens.sol";

import { $ } from "./network/$.sol";

contract Deployer is Ownable
{
	address constant DEFAULT_ADMIN = 0xBf70B751BB1FC725bFbC4e68C4Ec4825708766c5; // S

	uint256 constant INITIAL_WHEAT_PER_BLOCK = 1e18;

	address public admin;
	address public wheat;
	address public stkWheat;
	address public masterChef;

	bool public deployed = false;

	constructor () public
	{
		require($.NETWORK == $.network(), "wrong network");
	}

	function deploy() external onlyOwner
	{
		require(!deployed, "deploy unavailable");

		admin = DEFAULT_ADMIN;

		// configure MasterChef
		wheat = LibDeployer1.publish_WHEAT();
		stkWheat = LibDeployer1.publish_stkWHEAT(wheat);
		masterChef = LibDeployer2.publish_CustomMasterChef(wheat, stkWheat, INITIAL_WHEAT_PER_BLOCK, block.number);

		// transfer ownerships
		Ownable(wheat).transferOwnership(masterChef);
		Ownable(stkWheat).transferOwnership(masterChef);
		Ownable(masterChef).transferOwnership(admin);

		// wrap up the deployment
		renounceOwnership();
		deployed = true;
		emit DeployPerformed();
	}

	event DeployPerformed();
}

library LibDeployer1
{
	function publish_WHEAT() public returns (address _address)
	{
		return address(new WHEAT());
	}

	function publish_stkWHEAT(address _wheat) public returns (address _address)
	{
		return address(new stkWHEAT(_wheat));
	}
}

library LibDeployer2
{
	function publish_CustomMasterChef(address _wheat, address _stkWheat, uint256 _cakePerBlock, uint256 _startBlock) public returns (address _address)
	{
		return address(new CustomMasterChef(_wheat, _stkWheat, _cakePerBlock, _startBlock));
	}
}
