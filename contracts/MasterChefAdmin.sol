// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { CustomMasterChef } from "./CustomMasterChef.sol";
import { FeeCollector } from "./FeeCollector.sol";
import { RewardCompoundingStrategyToken } from "./RewardCompoundingStrategyToken.sol";

contract MasterChefAdmin is Ownable, ReentrancyGuard
{
	address public immutable masterChef;

	constructor (address _masterChef) public
	{
		masterChef = _masterChef;
	}

	function addToWhitelist(address _address) external onlyOwner nonReentrant
	{
		CustomMasterChef(masterChef).addToWhitelist(_address);
	}

	function removeFromWhitelist(address _address) external onlyOwner nonReentrant
	{
		CustomMasterChef(masterChef).removeFromWhitelist(_address);
	}

	function updateCakePerBlock(uint256 _cakePerBlock) external onlyOwner nonReentrant
	{
		CustomMasterChef(masterChef).updateCakePerBlock(_cakePerBlock);
	}

	function updateMultiplier(uint256 _multiplierNumber) external onlyOwner nonReentrant
	{
		CustomMasterChef(masterChef).updateMultiplier(_multiplierNumber);
	}

	function add(uint256 _allocPoint, address _lpToken, bool _withUpdate) external onlyOwner nonReentrant
	{
		CustomMasterChef(masterChef).add(_allocPoint, IERC20(_lpToken), _withUpdate);
	}

	function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external onlyOwner nonReentrant
	{
		CustomMasterChef(masterChef).set(_pid, _allocPoint, _withUpdate);
	}

	function addRewardCompoundingStrategy(string memory _name, string memory _symbol, uint8 _decimals,
		address _masterChef, uint256 _pid, address _routingToken, uint256 _allocPoint,
		address _buyback, address _exchange, address _dev, address _treasury) external onlyOwner nonReentrant
	{
		address _owner = msg.sender;
		address _collector = new_FeeCollector(_masterChef, _pid, _buyback, _treasury);
		address _strategy = LibMasterChefAdmin.new_RewardCompoundingStrategyToken(_name, _symbol, _decimals, _masterChef, _pid, _routingToken, _dev, _treasury, _collector);
		RewardCompoundingStrategyToken(_strategy).setExchange(_exchange);
		CustomMasterChef(masterChef).add(_allocPoint, IERC20(_strategy), false);
		if (_masterChef == masterChef) {
			CustomMasterChef(masterChef).addToWhitelist(_collector);
			CustomMasterChef(masterChef).addToWhitelist(_strategy);
		}
		Ownable(_collector).transferOwnership(_owner);
		Ownable(_strategy).transferOwnership(_owner);
	}

	function new_FeeCollector(address _masterChef, uint256 _pid, address _buyback, address _treasury) internal returns (address _address)
	{
		return address(new FeeCollector(_masterChef, _pid, _buyback, _treasury));
	}
}

library LibMasterChefAdmin
{
	function new_RewardCompoundingStrategyToken(string memory _name, string memory _symbol, uint8 _decimals,
		address _masterChef, uint256 _pid, address _routingToken,
		address _dev, address _treasury, address _collector) public returns (address _address)
	{
		return address(new RewardCompoundingStrategyToken(_name, _symbol, _decimals, _masterChef, _pid, _routingToken, _dev, _treasury, _collector));
	}
}
