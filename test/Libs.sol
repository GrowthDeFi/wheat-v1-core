// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Exchange } from "../contracts/Exchange.sol";
import { UniversalBuyback } from "../contracts/UniversalBuyback.sol";

library LibExchange
{
	function newExchange(address _router, address _treasury) public returns (address _exchange)
	{
		return address(new Exchange(_router, _treasury));
	}
}

library LibUniversalBuyback
{
	function newUniversalBuyback(address _rewardToken, address _buybackToken1, address _buybackToken2, address _treasury, address _exchange) public returns (address _buyback)
	{
		return address(new UniversalBuyback(_rewardToken, _buybackToken1, _buybackToken2, _treasury, _exchange));
	}
}

library LibPancakeSwapFeeCollector
{
	function newPancakeSwapFeeCollector(address _masterChef, uint256 _pid, address _routingToken, address _treasury, address _buyback, address _exchange) public returns (address _collector)
	{
		return address(new PancakeSwapFeeCollector(_masterChef, _pid, _routingToken, _treasury, _buyback, _exchange));
	}
}

library LibPancakeSwapCompoundingStrategyToken
{
	function newPancakeSwapCompoundingStrategyToken(string memory _name, string memory _symbol, uint8 _decimals, address _masterChef, uint256 _pid, address _routingToken, address _dev, address _treasury, address _collector, address _exchange) public returns (address _strategy)
	{
		return address(new PancakeSwapCompoundingStrategyToken(_name, _symbol, _decimals, _masterChef, _pid, _routingToken, _dev, _treasury, _collector, _exchange));
	}
}

library LibAutoFarmFeeCollectorAdapter
{
	function newAutoFarmFeeCollectorAdapter(address _sourceToken, address _targetToken, address _treasury, address _collector, address _exchange) public returns (address _collector)
	{
		return address(new AutoFarmFeeCollectorAdapter(_sourceToken, _targetToken, _treasury, _collector, _exchange));
	}
}

library LibAutoFarmCompoundingStrategyToken
{
	function newAutoFarmCompoundingStrategyToken(string memory _name, string memory _symbol, uint8 _decimals, address _autoFarm, uint256 _pid, address _routingToken, bool _useBelt, address _beltPool, uint256 _beltPoolIndex, address _treasury, address _collector, address _exchange) public returns (address _strategy)
	{
		return address(new AutoFarmCompoundingStrategyToken(_name, _symbol, _decimals, _autoFarm, _pid, _routingToken, _useBelt, _beltPool, _beltPoolIndex, _treasury, _collector, _exchange));
	}
}

library LibPantherSwapBuybackAdapter
{
	function newPantherSwapBuybackAdapter(address _sourceToken, address _targetToken, address _treasury, address _buyback, address _exchange) public returns (address _buyback)
	{
		return address(new PantherSwapBuybackAdapter(_sourceToken, _targetToken, _treasury, _buyback, _exchange));
	}
}

library LibPantherSwapCompoundingStrategyToken
{
	function newPantherSwapCompoundingStrategyToken(string memory _name, string memory _symbol, uint8 _decimals, address _masterChef, uint256 _pid, address _routingToken, address _dev, address _treasury, address _buyback, address _exchange) public returns (address _strategy)
	{
		return address(new PantherSwapCompoundingStrategyToken(_name, _symbol, _decimals, _masterChef,_pid, _routingToken, _dev, _treasury, _buyback, _exchange));
	}
}
