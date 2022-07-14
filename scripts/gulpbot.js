const fs = require('fs')
require('dotenv').config();
const axios = require('axios')
const Web3 = require('web3');
const HDWalletProvider = require('@truffle/hdwallet-provider');

// process

function idle() {
  return new Promise((resolve, reject) => { });
}

function sleep(delay) {
  return new Promise((resolve, reject) => setTimeout(resolve, delay));
}

function abort(e) {
  console.error(e || new Error('Program aborted'));
  process.exit(1);
}

function exit() {
  process.exit(0);
}

function interrupt(f) {
  process.on('SIGINT', f);
  process.on('SIGTERM', f);
  process.on('SIGUSR1', f);
  process.on('SIGUSR2', f);
  process.on('uncaughtException', f);
  process.on('unhandledRejection', f);
}

function entrypoint(main) {
  const args = process.argv;
  (async () => { try { await main(args); } catch (e) { abort(e); } exit(); })();
}

function randomInt(limit) {
  return Math.floor(Math.random() * limit)
}

// conversion

function valid(amount, decimals) {
  const regex = new RegExp(`^\\d+${decimals > 0 ? `(\\.\\d{1,${decimals}})?` : ''}$`);
  return regex.test(amount);
}

function coins(units, decimals) {
  if (!valid(units, 0)) throw new Error('Invalid amount');
  if (decimals == 0) return units;
  const s = units.padStart(1 + decimals, '0');
  return s.slice(0, -decimals) + '.' + s.slice(-decimals);
}

function units(coins, decimals) {
  if (!valid(coins, decimals)) throw new Error('Invalid amount');
  let i = coins.indexOf('.');
  if (i < 0) i = coins.length;
  const s = coins.slice(i + 1);
  return coins.slice(0, i) + s + '0'.repeat(decimals - s.length);
}

// web3

const privateKey = process.env['PRIVATE_KEY'] || '';
const ankrProjectId = process.env['ANKR_PROJECT_ID'] || '';
const ankrApikeyBscmain = process.env['ANKR_APIKEY_BSCMAIN'] || '';
const ankrApikeyBsctest = process.env['ANKR_APIKEY_BSCTEST'] || '';

const CHAIN_ID = {
  'bscmain': 56,
  'bsctest': 97,
  'avaxmain': 43114,
  'avaxtest': 43113,
  'ftmmain': 250,
  'ftmtest': 4002,
};

const NETWORK_NAME = {
  56: 'bscmain',
  97: 'bsctest',
  43114: 'avaxmain',
  43113: 'avaxtest',
  250: 'ftmmain',
  4002: 'ftmtest',
};

const ADDRESS_URL_PREFIX = {
  'bscmain': 'https://bscscan.com/address/',
  'bsctest': 'https://testnet.bscscan.com/address/',
  'avaxmain': 'https://snowtrace.io/address/',
  'avaxtest': 'https://testnet.snowtrace.io/address/',
  'ftmmain': 'https://ftmscan.com/address/',
  'ftmtest': 'https://testnet.ftmscan.com/address/',
};

const TX_URL_PREFIX = {
  'bscmain': 'https://bscscan.com/tx/',
  'bsctest': 'https://testnet.bscscan.com/tx/',
  'avaxmain': 'https://snowtrace.io/tx/',
  'avaxtest': 'https://testnet.snowtrace.io/tx/',
  'ftmmain': 'https://ftmscan.com/tx/',
  'ftmtest': 'https://testnet.ftmscan.com/tx/',
};

const NATIVE_SYMBOL = {
  'bscmain': 'BNB',
  'bsctest': 'BNB',
  'avaxmain': 'AVAX',
  'avaxtest': 'AVAX',
  'ftmmain': 'FTM',
  'ftmtest': 'FTM',
};

const LIMIT_GASPRICE = {
  'bscmain': '5000000000',
  'bsctest': '10000000000',
  'avaxmain': '100000000000',
  'avaxtest': '100000000000',
  'ftmmain': '3000000000000',
  'ftmtest': '3000000000000',
};

const HTTP_PROVIDER_URLS = {
  'bscmain': [
    'https://bsc-dataseed.binance.org/',
    'https://bsc-dataseed1.defibit.io/',
    'https://bsc-dataseed1.ninicoin.io/',
    'https://bsc-dataseed2.defibit.io/',
    'https://bsc-dataseed3.defibit.io/',
    'https://bsc-dataseed4.defibit.io/',
    'https://bsc-dataseed2.ninicoin.io/',
    'https://bsc-dataseed3.ninicoin.io/',
    'https://bsc-dataseed4.ninicoin.io/',
    'https://bsc-dataseed1.binance.org/',
    'https://bsc-dataseed2.binance.org/',
    'https://bsc-dataseed3.binance.org/',
    'https://bsc-dataseed4.binance.org/',
    // 'https://apis.ankr.com/' + ankrApikeyBscmain + '/' + ankrProjectId + '/binance/full/main',
  ],
  'bsctest': [
    'https://data-seed-prebsc-1-s1.binance.org:8545/',
    'https://data-seed-prebsc-2-s1.binance.org:8545/',
    'https://data-seed-prebsc-1-s2.binance.org:8545/',
    'https://data-seed-prebsc-2-s2.binance.org:8545/',
    'https://data-seed-prebsc-1-s3.binance.org:8545/',
    'https://data-seed-prebsc-2-s3.binance.org:8545/',
    // 'https://apis.ankr.com/' + ankrApikeyBsctest + '/' + ankrProjectId + '/binance/full/test',
  ],
  'avaxmain': [
    'https://api.avax.network/ext/bc/C/rpc',
  ],
  'avaxtest': [
    'https://api.avax-test.network/ext/bc/C/rpc',
  ],
  'ftmmain': [
    'https://rpc.ftm.tools/',
    // 'https://rpc.fantom.network/',
  ],
  'ftmtest': [
    'https://rpc.testnet.fantom.network/',
  ],
};

const web3Cache = {};

function getWeb3(privateKey, network) {
  let web3 = web3Cache[network];
  if (!web3) {
    const index = randomInt(HTTP_PROVIDER_URLS[network].length);
    const url = HTTP_PROVIDER_URLS[network][index];
    const options = { transactionConfirmationBlocks: 0 };
    web3 = new Web3(new HDWalletProvider(privateKey, url), null, options);
    web3Cache[network] = web3;
  }
  return web3;
}

// telegram

function escapeHTML(message) {
  return message
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

const telegramBotApiKey = process.env['TELEGRAM_BOT_API_KEY'] || '';
const telegramBotChatId = process.env['TELEGRAM_BOT_CHAT_ID'] || '';

let lastTelegramMessage;

async function sendTelegramMessage(message, key = '') {
  const filename = '/tmp/bridgebot-telegram-messages.json';
  if (lastTelegramMessage === undefined) {
    lastTelegramMessage = {};
    try { lastTelegramMessage = JSON.parse(fs.readFileSync(filename)); } catch { }
  }
  if (message !== lastTelegramMessage[key]) {
    console.log(new Date().toISOString());
    console.log(message);
    try {
      const url = 'https://api.telegram.org/bot'+ telegramBotApiKey +'/sendMessage';
      await axios.post(url, { chat_id: telegramBotChatId, text: message, parse_mode: 'HTML', disable_web_page_preview: true });
      lastTelegramMessage[key] = message;
    } catch (e) {
      console.error('FAILURE', e.message);
    }
  }
  try { fs.writeFileSync(filename, JSON.stringify(lastTelegramMessage, undefined, 2)); } catch { }
}

// lib

const IERC20_ABI = require('../build/contracts/IERC20.json').abi;
const MASTERCHEF_ABI = require('../build/contracts/CustomMasterChef.json').abi;
const MASTERCHEFJOE_ABI = require('../build/contracts/MasterChefJoe.json').abi;
const MASTERCHEFLQDR_ABI = require('../build/contracts/MasterChefLqdrV2.json').abi;
const STRATEGY_ABI = require('../build/contracts/RewardCompoundingStrategyToken.json').abi;
const COLLECTOR_ADAPTER_ABI = require('../build/contracts/AutoFarmFeeCollectorAdapter.json').abi;
const COLLECTOR_ABI = require('../build/contracts/FeeCollector.json').abi;
const BUYBACK_ABI = require('../build/contracts/Buyback.json').abi;
const UNIVERSAL_BUYBACK_ABI = require('../build/contracts/UniversalBuyback.json').abi;

const EXTENSION_ABI = [
  {
    type: 'function',
    name: 'collect',
    inputs: [],
    outputs:[],
  },
];

const MULTIREWARDALLOCATOR_ABI = [
  {
    type: 'function',
    name: 'unavailable',
    inputs: [],
    'stateMutability': 'view',
    outputs:[{ type: 'bool', name: '_flag' }],
  },
  {
    type: 'function',
    name: 'unallocated',
    inputs: [],
    'stateMutability': 'view',
    outputs:[{ type: 'bool', name: '_flag' }],
  },
  {
    type: 'function',
    name: 'allocate',
    inputs: [],
    outputs:[],
  },
];

const AMO_ABI = [
  {
    type: 'function',
    name: 'estimate',
    inputs: [],
    'stateMutability': 'view',
    outputs:[{ type: 'uint256', name: '_amount' }],
  },
  {
    type: 'function',
    name: 'collect',
    inputs: [],
    outputs:[],
  },
  {
    type: 'function',
    name: 'unbalanced',
    inputs: [],
    'stateMutability': 'view',
    outputs:[{ type: 'bool', name: '_flag' }],
  },
  {
    type: 'function',
    name: 'rebalance',
    inputs: [],
    outputs:[],
  },
];

const MASTERCHEFBOOV1_ABI = [
  {
    type: 'function',
    name: 'pendingBOO',
    inputs: [
      { type: 'uint256', name: '_pid' },
      { type: 'address', name: '_user' },
    ],
    'stateMutability': 'view',
    outputs:[{ type: 'uint256', name: '_amount' }],
  },
];

const MASTERCHEFBOOV2_ABI = [
  {
    type: 'function',
    name: 'rewarder',
    inputs: [{ type: 'uint256', name: '_pid' }],
    'stateMutability': 'view',
    outputs:[{ type: 'address', name: '_rewarder' }],
  },
];

const IREWARDER_ABI = [
  {
    type: 'function',
    name: 'pendingTokens',
    inputs: [
      { type: 'uint256', name: '_pid' },
      { type: 'address', name: '_user' },
      { type: 'uint256', name: '_amount' },
    ],
    'stateMutability': 'view',
    outputs:[
      { type: 'address[]', name: '_tokens' },
      { type: 'address[]', name: '_amounts' },
    ],
  },
];

const ACELAB_ABI = [
  {
    type: 'function',
    name: 'pendingReward',
    inputs: [
      { type: 'uint256', name: '_pid' },
      { type: 'address', name: '_user' },
    ],
    'stateMutability': 'view',
    outputs:[{ type: 'uint256', name: '_amount' }],
  },
];

const MASTERCHEF_ADDRESS = {
  'bscmain': '0x95fABAe2E9Fb0A269cE307550cAC3093A3cdB448',
  'bsctest': '0xF4748df5D63F6AB01e276065E6bD098Ce8dEA98a',
  'avaxmain': '0x5818388B1d756090FF1545D943fF9D1F6Ea13ce3',
  'avaxtest': '0x0000000000000000000000000000000000000000',
  'ftmmain': '0x0000000000000000000000000000000000000000',
  'ftmtest': '0x0000000000000000000000000000000000000000',
};

function getDefaultAccount(privateKey, network) {
  const web3 = getWeb3(privateKey, network);
  const [account] = web3.currentProvider.getAddresses();
  return account;
}

async function getNonce(privateKey, network, account = null) {
  const web3 = getWeb3(privateKey, network);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const nonce = await web3.eth.getTransactionCount(account);
    return nonce;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function getNativeBalance(privateKey, network, account = null) {
  const web3 = getWeb3(privateKey, network);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const amount = await web3.eth.getBalance(account);
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function getTokenBalance(privateKey, network, address, account = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = IERC20_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.balanceOf(account).call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function getTokenSymbol(privateKey, network, address) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  try {
    const symbol = await contract.methods.symbol().call();
    return symbol;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function getPendingBalance(privateKey, network, address, pid, account = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = MASTERCHEF_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.pendingCake(pid, account).call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function getPendingBalanceJoe(privateKey, network, address, pid, account = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = MASTERCHEFJOE_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const { _pendingJoe: amount } = await contract.methods.pendingTokens(pid, account).call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function getPendingBalanceLqdr(privateKey, network, address, pid, account = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = MASTERCHEFLQDR_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.pendingLqdr(pid, account).call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function getPendingBalanceAceLab(privateKey, network, address, pid, account = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = ACELAB_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.pendingReward(pid, account).call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function getPendingBalanceBoo(privateKey, network, address, pid, account = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = MASTERCHEFBOOV1_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.pendingBOO(pid, account).call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function getPendingBalanceDeus(privateKey, network, address, pid, account = null) {
  const web3 = getWeb3(privateKey, network);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  let rewarder;
  {
    const abi = MASTERCHEFBOOV2_ABI;
    const contract = new web3.eth.Contract(abi, address);
    try {
      rewarder = await contract.methods.rewarder(pid).call();
    } catch (e) {
      throw new Error(e.message);
    }
  }
  {
    const abi = IREWARDER_ABI;
    const contract = new web3.eth.Contract(abi, rewarder);
    try {
      const response = await contract.methods.pendingTokens(pid, account, 0).call();
      const amount = response._amounts[0];
      return amount;
    } catch (e) {
      throw new Error(e.message);
    }
  }
}

async function pendingReward(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.pendingReward().call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function performanceFee(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.performanceFee().call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function pendingPerformanceFee(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.pendingPerformanceFee().call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function getCollector(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const collector = await contract.methods.collector().call();
    return collector;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function pendingDeposit(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = COLLECTOR_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.pendingDeposit().call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function getBuyback(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = COLLECTOR_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const buyback = await contract.methods.buyback().call();
    return buyback;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function pendingBuyback(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = BUYBACK_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.pendingBuyback().call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function pendingSource(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = COLLECTOR_ADAPTER_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.pendingSource().call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function pendingTarget(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = COLLECTOR_ADAPTER_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.pendingTarget().call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function pendingBurning(privateKey, network, address, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = UNIVERSAL_BUYBACK_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const { _burning1, _burning2 } = await contract.methods.pendingBurning().call();
    return [_burning1, _burning2];
  } catch (e) {
    throw new Error(e.message);
  }
}

async function collect(privateKey, network, address, nonce, limitGas = true) {
  const web3 = getWeb3(privateKey, network);
  const abi = EXTENSION_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const [from] = web3.currentProvider.getAddresses();
  let txId = null;
  try {
    const estimatedGas = await contract.methods.collect().estimateGas({ from, nonce });
    const gas = 2 * estimatedGas;
    if (limitGas) {
      const gasPrice = await web3.eth.getGasPrice();
      if (BigInt(gasPrice) > BigInt(LIMIT_GASPRICE[network])) {
        throw new Error('Gas price beyond the set limit');
      }
    }
    await contract.methods.collect().send({ from, nonce, gas })
      .on('transactionHash', (hash) => {
        txId = hash;
      });
  } catch (e) {
    throw new Error(e.message);
  }
  if (txId === null) throw new Error('Failure reading txId');
  return txId;
}

async function unavailable(privateKey, network, address, account = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = MULTIREWARDALLOCATOR_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const flag = await contract.methods.unavailable().call();
    return flag;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function unallocated(privateKey, network, address, account = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = MULTIREWARDALLOCATOR_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const flag = await contract.methods.unallocated().call();
    return flag;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function allocate(privateKey, network, address, nonce, limitGas = true) {
  const web3 = getWeb3(privateKey, network);
  const abi = MULTIREWARDALLOCATOR_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const [from] = web3.currentProvider.getAddresses();
  let txId = null;
  try {
    const estimatedGas = await contract.methods.allocate().estimateGas({ from, nonce });
    const gas = 2 * estimatedGas;
    if (limitGas) {
      const gasPrice = await web3.eth.getGasPrice();
      if (BigInt(gasPrice) > BigInt(LIMIT_GASPRICE[network])) {
        throw new Error('Gas price beyond the set limit');
      }
    }
    await contract.methods.allocate().send({ from, nonce, gas })
      .on('transactionHash', (hash) => {
        txId = hash;
      });
  } catch (e) {
    throw new Error(e.message);
  }
  if (txId === null) throw new Error('Failure reading txId');
  return txId;
}

async function estimate(privateKey, network, address, account = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = AMO_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const amount = await contract.methods.estimate().call();
    return amount;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function unbalanced(privateKey, network, address, account = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = AMO_ABI;
  const contract = new web3.eth.Contract(abi, address);
  if (account === null) [account] = web3.currentProvider.getAddresses();
  try {
    const flag = await contract.methods.unbalanced().call();
    return flag;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function rebalance(privateKey, network, address, nonce, limitGas = true) {
  const web3 = getWeb3(privateKey, network);
  const abi = AMO_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const [from] = web3.currentProvider.getAddresses();
  let txId = null;
  try {
    const estimatedGas = await contract.methods.rebalance().estimateGas({ from, nonce });
    const gas = 2 * estimatedGas;
    if (limitGas) {
      const gasPrice = await web3.eth.getGasPrice();
      if (BigInt(gasPrice) > BigInt(LIMIT_GASPRICE[network])) {
        throw new Error('Gas price beyond the set limit');
      }
    }
    await contract.methods.rebalance().send({ from, nonce, gas })
      .on('transactionHash', (hash) => {
        txId = hash;
      });
  } catch (e) {
    throw new Error(e.message);
  }
  if (txId === null) throw new Error('Failure reading txId');
  return txId;
}

async function gulp0(privateKey, network, address, nonce, limitGas = true) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const [from] = web3.currentProvider.getAddresses();
  let txId = null;
  try {
    const estimatedGas = await contract.methods.gulp().estimateGas({ from, nonce });
    const gas = 2 * estimatedGas;
    if (limitGas) {
      const gasPrice = await web3.eth.getGasPrice();
      if (BigInt(gasPrice) > BigInt(LIMIT_GASPRICE[network])) {
        throw new Error('Gas price beyond the set limit');
      }
    }
    await contract.methods.gulp().send({ from, nonce, gas })
      .on('transactionHash', (hash) => {
        txId = hash;
      });
  } catch (e) {
    throw new Error(e.message);
  }
  if (txId === null) throw new Error('Failure reading txId');
  return txId;
}

async function gulp1(privateKey, network, address, amount, nonce, limitGas = true) {
  const web3 = getWeb3(privateKey, network);
  const abi = COLLECTOR_ADAPTER_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const [from] = web3.currentProvider.getAddresses();
  let txId = null;
  try {
    const estimatedGas = await contract.methods.gulp(amount).estimateGas({ from, nonce });
    const gas = 2 * estimatedGas;
    if (limitGas) {
      const gasPrice = await web3.eth.getGasPrice();
      if (BigInt(gasPrice) > BigInt(LIMIT_GASPRICE[network])) {
        throw new Error('Gas price beyond the set limit');
      }
    }
    await contract.methods.gulp(amount).send({ from, nonce, gas })
      .on('transactionHash', (hash) => {
        txId = hash;
      });
  } catch (e) {
    throw new Error(e.message);
  }
  if (txId === null) throw new Error('Failure reading txId');
  return txId;
}

async function gulp2(privateKey, network, address, amount1, amount2, nonce, limitGas = true) {
  const web3 = getWeb3(privateKey, network);
  const abi = UNIVERSAL_BUYBACK_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const [from] = web3.currentProvider.getAddresses();
  let txId = null;
  try {
    const estimatedGas = await contract.methods.gulp(amount1, amount2).estimateGas({ from, nonce });
    const gas = 2 * estimatedGas;
    if (limitGas) {
      const gasPrice = await web3.eth.getGasPrice();
      if (BigInt(gasPrice) > BigInt(LIMIT_GASPRICE[network])) {
        throw new Error('Gas price beyond the set limit');
      }
    }
    await contract.methods.gulp(amount1, amount2).send({ from, nonce, gas })
      .on('transactionHash', (hash) => {
        txId = hash;
      });
  } catch (e) {
    throw new Error(e.message);
  }
  if (txId === null) throw new Error('Failure reading txId');
  return txId;
}

async function poolLength(privateKey, network, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = MASTERCHEF_ABI;
  const address = MASTERCHEF_ADDRESS[network];
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const length = await contract.methods.poolLength().call();
    return length;
  } catch (e) {
    throw new Error(e.message);
  }
}

async function poolInfo(privateKey, network, pid, agent = null) {
  const web3 = getWeb3(privateKey, network);
  const abi = MASTERCHEF_ABI;
  const address = MASTERCHEF_ADDRESS[network];
  const contract = new web3.eth.Contract(abi, address);
  if (agent === null) [agent] = web3.currentProvider.getAddresses();
  try {
    const { lpToken } = await contract.methods.poolInfo(pid).call();
    return { lpToken };
  } catch (e) {
    throw new Error(e.message);
  }
}

// app

const ACTIVE_PIDS = [
  5,
  // 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28,
  33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
  48, 49, 50, 51
];
const MONITORING_INTERVAL = 15; // 15 seconds
const DEFAULT_GULP_INTERVAL = 4 * 60 * 60; // 4 hours
const GULP_INTERVAL = {
  // cLQDR Extension
  '0x30d1900306FD84EcFBCb16F821Aba69054aca15C': 24 * 60 * 60, // 24 hours
  // cLQDR Receiver (obsolete)
  // '0x6f1c4303bC40AEee0aa60dD90e4eeC353487b66f': 24 * 60 * 60, // 24 hours
  // cLQDR Receiver
  '0xCD3563CD8dE2602701d5d9f960db30710fcc4053': 24 * 60 * 60, // 24 hours

  // MRA [Avalanche]
  '0x6adf0cd8BE6b8cF7149C443dA8D4F7Ca942EB9B5': 5 * 60, // 5 minutes

  // MRA [BSC]
  '0x07c3c8350b341179582CA5e6C4BF04fEC5Cf5392': 5 * 60, // 5 minutes

  // MRA [Fantom]
  '0xD51fd17f7d5B4C4486257bad5553dB3689F9FCe2': 5 * 60, // 5 minutes

  // MOR/bb-yv-USD AMO [Fantom]
  '0x53AAF3c5FC977E2ED7E0e746306Dec3927829AE5': 12 * 60 * 60, // 12 hours

  // Payroll [Fantom]
  '0x7AA3136a31Dd238E1413294a8b89689f97073625': 5 * 60, // 5 minutes

/*
  // 5 - stkCAKE
  '0x84BA65DB2da175051E25F86e2f459C863CBb3E0C': 24 * 60 * 60, // 24 hours

  // 18 - stkBNB/CAKE
  // '0x4291474e88E2fEE6eC5B8c28F4Ed2075cEf5B803': 12 * 60 * 60, // 12 hours
  // 19 - stkBNB/BUSD
  // '0xdC4D358B34619e4fE7feb28bE301B2FBe4F3aFf9': 24 * 60 * 60, // 24 hours
  // 20 - stkBNB/BTCB
  // '0xA561fa603bf0B43Cb0d0911EeccC8B6777d3401B': 24 * 60 * 60, // 24 hours
  // 21 - stkBNB/ETH
  // '0x28e6aa3DD98372Da0959Abe9d0efeB4455d4dFe1': 24 * 60 * 60, // 24 hours
  // 22 - stkBNB/LINK
  // '0x3B88a64D0B9fA485B71c98B00D799aa8D1aEe9E3': 24 * 60 * 60, // 24 hours
  // 23 - stkBNB/UNI
  // '0x515785CE5D5e94f93fe41Ed3fd83779Fb3Aff8A4': 24 * 60 * 60, // 24 hours
  // 24 - stkBNB/DOT
  // '0x53073f685474341cdc765F97E7CFB2F427BD9db9': 24 * 60 * 60, // 24 hours
  // 25 - stkBNB/ADA
  // '0xf5aFfe3459813AB193329E53f17098806709046A': 24 * 60 * 60, // 24 hours
  // 26 - stkBUSD/UST
  // '0x5141da4ab5b3e13ceE7B10980aE6bB848FdB59Cd': 24 * 60 * 60, // 24 hours
  // 27 - stkBUSD/DAI
  // '0x691e486b5F7E39e90d37485164fAbDDd93aE43cD': 24 * 60 * 60, // 24 hours
  // 28 - stkBUSD/USDC
  // '0xae35A19F1DAc62AD3794773D5f0983f05073D0f2': 24 * 60 * 60, // 24 hours

  // 33 - stkBNB/CAKEv2
  '0x86c15Efe94320Cd139eA4875b7ceF336e1F91f16': 36 * 60 * 60, // 36 hours
  // 34 - stkBNB/BUSDv2
  '0xd5ffd8318b1c82FDE321f7BC1a553462A13A2E14': 36 * 60 * 60, // 36 hours
  // 35 - stkBNB/USDTv2
  '0x7259CeBc6D8f84afdce4B81a3a33D53A526521F8': 72 * 60 * 60, // 72 hours
  // 36 - stkBNB/BTCBv2
  '0x074fD0f3289cF3F5E0E80c969F62B21cB38Ad3b5': 72 * 60 * 60, // 72 hours
  // 37 - stkBNB/ETHv2
  '0x15B310c8D9d0Ac9aefB94BF492e7eAbC43B4f93e': 72 * 60 * 60, // 72 hours
  // 38 - stkBUSD/USDTv2
  '0x6f1c4303bC40AEee0aa60dD90e4eeC353487b66f': 72 * 60 * 60, // 72 hours
  // 39 - stkBUSD/VAIv2
  '0xC8daDd57BD9342b7ba9449B952DBE11B4f3D1648': 72 * 60 * 60, // 72 hours
  // 40 - stkBNB/DOTv2
  '0x5C96941B28B824c3E9d01E5cb2D77B3f7801560e': 72 * 60 * 60, // 72 hours
  // 41 - stkBNB/LINKv2
  '0x501382584a3DBF1471918Cd4ee0fd3bE23FfDF29': 72 * 60 * 60, // 72 hours
  // 42 - stkBNB/UNIv2
  '0x0900a05910E7d4811f9FC17843120D6412df2968': 72 * 60 * 60, // 72 hours
  // 43 - stkBNB/DODOv2
  '0x67A4c8d130ED95fFaB9F2CDf001811Ada1077875': 72 * 60 * 60, // 72 hours
  // 44 - stkBNB/ALPHAv2
  '0x6C6d105066462EE9b5Cfc7628e2edB1000e887F1': 72 * 60 * 60, // 72 hours
  // 45 - stkBNB/ADAv2
  '0x73099318dfBB1C59e473322F29C215132A14Ab86': 72 * 60 * 60, // 72 hours
  // 46 - stkBUSD/USTv2
  '0xB2b5dba919Da2E06d6cDd15dF17bA4b99D3eB1bD': 72 * 60 * 60, // 72 hours
  // 47 - stkBUSD/BTCBv2
  '0xf30D01da4257c696e537E2fdF0a2Ce6C9D627352': 72 * 60 * 60, // 72 hours
  // 48 - stkbeltBNBv2
  '0xeC97D2e53e34Aa8E5C6a843D9cd74641E645681A': 48 * 60 * 60, // 48 hours
  // 49 - stkbeltBTCv2
  '0x04abDB55DCd0167BFcE8FA0fA125F102c4734C62': 48 * 60 * 60, // 48 hours
  // 50 - stkbeltETHv2
  '0xE70aA236f2c2dABC346e193F606986Bb843bA3d9': 48 * 60 * 60, // 48 hours
  // 51 - stk4BELTv2
  '0xeB8e1c316694742E7042882be1ac55ebbD2bCEbB': 48 * 60 * 60, // 48 hours

  // - stkBNB/BUSDv2
  '0x4046492479a5bA18c2a947A1db75f4f1ef227BF1': 72 * 60 * 60, // 72 hours
  // - stkBNB/BTCBv2
  '0xc1d3F1dB60DE17afD7770464BAb05c58129d7Ee0': 72 * 60 * 60, // 72 hours
  // - stkBNB/ETHv2
  '0x9C009595F330CA8070e78b889183e7b8a96cB962': 72 * 60 * 60, // 72 hours
  // - stkBNB/CAKEv2
  '0x1f48dCbCE7fC91180492a7b083472924b4e8a44b': 72 * 60 * 60, // 72 hours
  // - stkBUSD/USDCv2
  '0xd802621F65Bd96D76e84E49EecdED49C5acb105d': 72 * 60 * 60, // 72 hours
  // - stkBNB/USDTv2
  '0xE0327dA3f94Efe600569Ca68Aa02e6921FD89Bfa': 72 * 60 * 60, // 27 hours
  // - stkBNB/PANTHERv2
  '0x358582CEeeB0F008495C06206973F5F6e495accd': 24 * 60 * 60, // 24 hours
  // - stkBUSD/PANTHERv2
  '0x1A51686Fb42861AA7E38c1CF8868877F43F82aA4': 24 * 60 * 60, // 24 hours

  // CAKE collector
  '0x14bAc5f216337F8da5f41Bb920514Af98ef62c36': 24 * 60 * 60, // 24 hours
  // AUTO/CAKE collector adapter
  '0x626E98ef225A6f79523C9004E8731B793dfd0F68': 48 * 60 * 60, // 48 hours
  // CAKE buyback
  '0xC351706C3212D45fc24F6B89e686f07fAb048b16': 24 * 60 * 60, // 24 hours

  // PANTHER buyback adapter
  '0x495089390569d47807F1Db83F14e053002DB25b4': 48 * 60 * 60, // 48 hours
  // Universal buyback
  '0x01d1c4eC99D0A7D8f4141D42D1624fffa054D7Ae': 48 * 60 * 60, // 48 hours
*/
};

const strategyCache = {};

async function readStrategy(privateKey, network, pid) {
  if (strategyCache[pid]) return strategyCache[pid];
  const { lpToken: strategy } = await poolInfo(privateKey, network, pid);
  strategyCache[pid] = strategy;
  return strategy;
}

const collectorCache = {};

async function readCollector(privateKey, network, strategy) {
  if (collectorCache[strategy]) return collectorCache[strategy];
  const collector = await getCollector(privateKey, network, strategy);
  collectorCache[strategy] = collector;
  return collector;
}

const buybackCache = {};

async function readBuyback(privateKey, network, collector) {
  if (collectorCache[collector]) return collectorCache[collector];
  const buyback = await getBuyback(privateKey, network, collector);
  collectorCache[collector] = buyback;
  return buyback;
}

let lastGulp = {};

function readLastGulp(network) {
  try { lastGulp = JSON.parse(fs.readFileSync('gulpbot-' + network + '.json')); } catch (e) { }
}

function writeLastGulp(network) {
  try { fs.writeFileSync('gulpbot-' + network + '.json', JSON.stringify(lastGulp, undefined, 2)); } catch (e) { }
}

async function safeGulp(privateKey, network, address, limitGas = true) {
  const now = Date.now();
  const timestamp = lastGulp[address] || 0;
  const ellapsed = (now - timestamp) / 1000;
  const interval = GULP_INTERVAL[address] || DEFAULT_GULP_INTERVAL;
  if (ellapsed < interval) return null;
  const nonce = await getNonce(privateKey, network);
  try {
    let messages = [address];
    try { const txId = await gulp0(privateKey, network, address, nonce, limitGas); return txId; } catch (e) { messages.push(e.message); }
    try { const txId = await gulp1(privateKey, network, address, 0, nonce, limitGas); return txId; } catch (e) { messages.push(e.message); }
    try { const txId = await gulp2(privateKey, network, address, 0, 0, nonce, limitGas); return txId; } catch (e) { messages.push(e.message); }
    throw new Error(messages.join('\n'));
  } finally {
    lastGulp[address] = now;
    writeLastGulp(network);
  }
}

async function safeCollect(privateKey, network, address, limitGas = true) {
  const now = Date.now();
  const timestamp = lastGulp[address] || 0;
  const ellapsed = (now - timestamp) / 1000;
  const interval = GULP_INTERVAL[address] || DEFAULT_GULP_INTERVAL;
  if (ellapsed < interval) return null;
  const nonce = await getNonce(privateKey, network);
  try {
    let messages = [address];
    try { const txId = await collect(privateKey, network, address, nonce, limitGas); return txId; } catch (e) { messages.push(e.message); }
    throw new Error(messages.join('\n'));
  } finally {
    lastGulp[address] = now;
    writeLastGulp(network);
  }
}

async function safeAllocate(privateKey, network, address, limitGas = true) {
  const now = Date.now();
  const timestamp = lastGulp[address] || 0;
  const ellapsed = (now - timestamp) / 1000;
  const interval = GULP_INTERVAL[address] || DEFAULT_GULP_INTERVAL;
  if (ellapsed < interval) return null;
  const nonce = await getNonce(privateKey, network);
  try {
    let messages = [address];
    try { const txId = await allocate(privateKey, network, address, nonce, limitGas); return txId; } catch (e) { messages.push(e.message); }
    throw new Error(messages.join('\n'));
  } finally {
    lastGulp[address] = now;
    writeLastGulp(network);
  }
}

async function safeRebalance(privateKey, network, address, limitGas = true) {
  const now = Date.now();
  const timestamp = lastGulp[address] || 0;
  const ellapsed = (now - timestamp) / 1000;
  const interval = GULP_INTERVAL[address] || DEFAULT_GULP_INTERVAL;
  if (ellapsed < interval) return null;
  const nonce = await getNonce(privateKey, network);
  try {
    let messages = [address];
    try { const txId = await rebalance(privateKey, network, address, nonce, limitGas); return txId; } catch (e) { messages.push(e.message); }
    throw new Error(messages.join('\n'));
  } finally {
    lastGulp[address] = now;
    writeLastGulp(network);
  }
}

async function listContracts(privateKey, network) {
  const length = await poolLength(privateKey, network);
  console.log('pid', 'strategy', 'collector', 'buyback');
  for (let pid = 0; pid < length; pid++) {
    if (!ACTIVE_PIDS.includes(pid)) continue;
    const strategy = await readStrategy(privateKey, network, pid);
    const collector = await readCollector(privateKey, network, strategy);
    const buyback = await readBuyback(privateKey, network, collector);
    console.log(pid, strategy, collector, buyback);
  }
}

async function fixTwap(privateKey, network, address, exchange, rewardToken, routingToken, reserveToken, limitGas = true) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const [from] = web3.currentProvider.getAddresses();
  try {
    await contract.methods.gulp().estimateGas({ from });
  } catch {
    const abi = [
      {
        name: "oracleAveragePriceFactorFromInput",
        type: 'function',
        inputs: [
          { name: '_from', type: 'address' },
          { name: '_to', type: 'address' },
          { name: '_inputAmount', type: 'uint256' },
        ],
        outputs: [
          { name: '_factor', type: 'uint256' },
        ],
      },
      {
        name: 'oraclePoolAveragePriceFactorFromInput',
        type: 'function',
        inputs: [
          { name: '_pool', type: 'address' },
          { name: '_token', type: 'address' },
          { name: '_inputAmount', type: 'uint256' },
        ],
        outputs: [
          { name: '_factor', type: 'uint256' },
        ],
      },
    ];
    const gas = 300000;
    const contract = new web3.eth.Contract(abi, exchange, { from, gas });
    if (rewardToken !== routingToken) {
      try {
        if (limitGas) {
          const gasPrice = await web3.eth.getGasPrice();
          if (BigInt(gasPrice) > BigInt(LIMIT_GASPRICE[network])) {
            throw new Error('Gas price beyond the set limit');
          }
        }
        await contract.methods.oracleAveragePriceFactorFromInput(rewardToken, routingToken, '10000000000').estimateGas({ from });
        let txId = null;
        await contract.methods.oracleAveragePriceFactorFromInput(rewardToken, routingToken, '10000000000').send()
          .on('receipt', ({ transactionHash }) => { txId = transactionHash; });
        if (txId === null) throw new Error('Invalid txId');
      } catch (e) {
        throw Error('TWAP pool update ' + address + ': ' + exchange + ': ' + rewardToken + ': ' + routingToken + ': ' + e.message);
      }
    }
    if (reserveToken !== routingToken) {
      try {
        if (limitGas) {
          const gasPrice = await web3.eth.getGasPrice();
          if (BigInt(gasPrice) > BigInt(LIMIT_GASPRICE[network])) {
            throw new Error('Gas price beyond the set limit');
          }
        }
        await contract.methods.oraclePoolAveragePriceFactorFromInput(reserveToken, routingToken, '10000000000').estimateGas({ from });
        let txId = null;
        await contract.methods.oraclePoolAveragePriceFactorFromInput(reserveToken, routingToken, '10000000000').send()
          .on('receipt', ({ transactionHash }) => { txId = transactionHash; });
        if (txId === null) throw new Error('Invalid txId');
      } catch (e) {
        throw Error('TWAP pool update ' + address + ': ' + exchange + ': ' + reserveToken + ': ' + routingToken + ': ' + e.message);
      }
    }
  }
}

async function gulpAll(privateKey, network) {

  if (network === 'ftmmain') {

    const LQDR = '0x10b620b2dbAC4Faa7D7FFD71Da486f5D44cd86f9';
    const LQDR_MASTERCHEF_V2 = '0x6e2ad6527901c9664f016466b8DA1357a004db0f';
    const BOO_MASTERCHEF_V1 = '0x2b2929E785374c651a81A63878Ab22742656DcDd';
    const BOO_MASTERCHEF_V2 = '0x18b4f774fdC7BF685daeeF66c2990b1dDd9ea6aD';
    const XBOO_ACELAB = '0x2352b745561e7e6FCD03c093cE7220e3e126ace0';
    const WFTM = '0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83';
    const GEIST = '0xd8321AA83Fb0a4ECd6348D4577431310A6E0814d';
    const CRV = '0x1E4F97b9f9F913c46F1632781732927B9019C68b';
    const USDC = '0x04068DA6C83AFCFA0e13ba15A6696662335D5B75';
    const BOO = '0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE';
    const DEUS = '0xDE5ed76E7c05eC5e4572CfC88d1ACEA165109E44';
    const XBOO = '0xa48d959AE2E88f1dAA7D5F611E01908106dE7598';
    const BEFTM = '0x7381eD41F6dE418DdE5e84B55590422a57917886';
    const PGK = '0x188a168280589bC3E483d77aae6b4A1d26bD22dC';
    const SPI_EXCHANGE = '0x7c50808E072a5531eC5D3DCc88Bd7a4Afc36dbf9';
    const SPO_EXCHANGE = '0x3FDbFdc60Cf80465E7dC05041AE4f03E5e2D55cB';
    const SPI_FTM_LQDR = '0x4Fe6f19031239F105F753D1DF8A0d24857D0cAA2';
    const SPI_FTM_FUSDT = '0xd14Dd3c56D9bc306322d4cEa0E1C49e9dDf045D4';
    const SPI_FTM_WBTC = '0x279b2c897737a50405ED2091694F225D83F2D3bA';
    const SPI_FTM_USDC = '0xe7E90f5a767406efF87Fdad7EB07ef407922EC1D';
    const SPI_FTM_WETH = '0x613BF4E46b4817015c01c6Bb31C7ae9edAadc26e';
    const SPI_FTM_MIM = '0xB32b31DfAfbD53E310390F641C7119b5B9Ea0488';
    const SPI_FTM_SPIRIT = '0x30748322B6E34545DBe0788C421886AEB5297789';
    const SPI_FTM_FRAX = '0x7ed0cdDB9BB6c6dfEa6fB63E117c8305479B8D7D';
    const SPI_FTM_MAI = '0x51Eb93ECfEFFbB2f6fE6106c4491B5a0B944E8bd';
    const SPO_FTM_BOO = '0xEc7178F4C41f346b2721907F5cF7628E388A7a58';
    const SPO_FTM_USDC = '0x2b4C76d0dc16BE1C31D4C1DC53bF9B45987Fc75c';
    const SPO_FTM_DAI = '0xe120ffBDA0d14f3Bb6d6053E90E63c572A66a428';
    const SPO_FTM_SUSHI = '0xf84E313B36E86315af7a06ff26C8b20e9EB443C3';
    const SPO_FTM_LINK = '0x89d9bC2F2d091CfBFc31e333D6Dc555dDBc2fd29';
    const SPO_FTM_WETH = '0xf0702249F4D3A25cD3DED7859a165693685Ab577';
    const SPO_FTM_FUSDT = '0x5965E53aa80a0bcF1CD6dbDd72e6A9b2AA047410';
    const SPO_FTM_MIM = '0x6f86e65b255c9111109d2D2325ca2dFc82456efc';
    const SPO_FTM_SCREAM = '0x30872e4fc4edbFD7a352bFC2463eb4fAe9C09086';
    const SPO_USDC_DEI = '0xD343b8361Ce32A9e570C1fC8D4244d32848df88B';
    const SPO_FTM_DEUS = '0xaF918eF5b9f33231764A5557881E6D3e5277d456';

    {
      // LQDR SpiritSwap strategies
      const addresses = [
        // 0 - stkFTM/LQDRv3
        [0, '0x2FD8e6458f8AEA3C3370Ecf3357D754412c97C70', WFTM, SPI_FTM_LQDR, LQDR_MASTERCHEF_V2],
        // 3 - stkFTM/fUSDTv3
        [3, '0x83CbBea0074711dcbED2CB7936A22F4C59D624a7', WFTM, SPI_FTM_FUSDT, LQDR_MASTERCHEF_V2],
        // 4 - stkFTM/WBTCv3
        [4, '0x1fb4Abc302B2EB5ed3c4dD59C884eBB2b0cD1528', WFTM, SPI_FTM_WBTC, LQDR_MASTERCHEF_V2],
        // 5 - stkFTM/USDCv3
        [5, '0x0697ef69527147A3757516ecF6b1ff45652A2298', WFTM, SPI_FTM_USDC, LQDR_MASTERCHEF_V2],
        // 6 - stkFTM/WETHv3
        [6, '0x50714fF57E8cCf127E27Eba5Dfd1b82a4F918FE3', WFTM, SPI_FTM_WETH, LQDR_MASTERCHEF_V2],
        // 7 - stkFTM/MIMv3
        [7, '0xDA2AE62e2B71ad3000BB75acdA2F8f68DC88aCE4', WFTM, SPI_FTM_MIM, LQDR_MASTERCHEF_V2],
        // 28 - stkFTM/SPIRITv3
        [28, '0xF99A8Cd2b651893A3F8fb1045E4101e63D82264c', WFTM, SPI_FTM_SPIRIT, LQDR_MASTERCHEF_V2],
        // 3 - stkFTM/FRAXv3
        [33, '0xC1D8EE2b67440e2bae0Ca608F3DC0a5D3B83eE0F', WFTM, SPI_FTM_FRAX, LQDR_MASTERCHEF_V2],
        // 38 - stkFTM/MAIv3
        [38, '0x4cea7726Eea4a0B342f8422D003Df735eAfDB195', WFTM, SPI_FTM_MAI, LQDR_MASTERCHEF_V2],
      ];
      for (const [pid, address, routingToken, reserveToken, masterChef] of addresses) {
        const amount1 = await getTokenBalance(privateKey, network, LQDR, address);
        const amount2 = await getPendingBalanceLqdr(privateKey, network, masterChef, pid, address);
        const MINIMUM_AMOUNT = 20000000000000000000n; // 20 LQDR
        if (BigInt(amount1) + BigInt(amount2) >= MINIMUM_AMOUNT) {
          await fixTwap(privateKey, network, address, SPI_EXCHANGE, LQDR, routingToken, reserveToken);
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'SpiritSwapStrategy', address, tx };
          }
        }
      }
    }

    {
      // LQDR SpookySwap strategies
      const addresses = [
        // 10 - stkFTM/BOOv3
        [10, '0x2f797A09AcD7012782714EC62a64c02Db4Cd6d45', WFTM, SPO_FTM_BOO, LQDR_MASTERCHEF_V2],
        // 11 - stkFTM/USDCv3
        [11, '0x91CFBb392e6aF98e1b0fDD483b660bAFd049f61F', WFTM, SPO_FTM_USDC, LQDR_MASTERCHEF_V2],
        // 12 - stkFTM/DAIv3
        [12, '0xaFe49F040F934174A9FDFf24b1F219047dC3225e', WFTM, SPO_FTM_DAI, LQDR_MASTERCHEF_V2],
        // 13 - stkFTM/SUSHIv3
        [13, '0x9b1E10f73851B0d2bF401E0e82260eF64740296F', WFTM, SPO_FTM_SUSHI, LQDR_MASTERCHEF_V2],
        // 14 - stkFTM/LINKv3
        [14, '0x3B758ee4ffa3f29ec0827ED5939F0595c53c5e42', WFTM, SPO_FTM_LINK, LQDR_MASTERCHEF_V2],
        // 15 - stkFTM/WETHv3
        [15, '0x1c312bcf04B4640516894D1e8AC20B8CcC764c0E', WFTM, SPO_FTM_WETH, LQDR_MASTERCHEF_V2],
        // 16 - stkFTM/fUSDTv3
        [16, '0x91D350d539dCFc8a88e665C1247283ef4bF2FD7e', WFTM, SPO_FTM_FUSDT, LQDR_MASTERCHEF_V2],
        // 17 - stkFTM/MIMv3
        [17, '0x7abF269faC9E8324dE364F26ed3B8379C7F0629E', WFTM, SPO_FTM_MIM, LQDR_MASTERCHEF_V2],
        // 23 - stkFTM/SCREAMv3
        [23, '0x4d5727523127cfE9F0088f05bCa9B2afd4Ac87e5', WFTM, SPO_FTM_SCREAM, LQDR_MASTERCHEF_V2],
      ];
      for (const [pid, address, routingToken, reserveToken, masterChef] of addresses) {
        const amount1 = await getTokenBalance(privateKey, network, LQDR, address);
        const amount2 = await getPendingBalanceLqdr(privateKey, network, masterChef, pid, address);
        const MINIMUM_AMOUNT = 20000000000000000000n; // 20 LQDR
        if (BigInt(amount1) + BigInt(amount2) >= MINIMUM_AMOUNT) {
          await fixTwap(privateKey, network, address, SPO_EXCHANGE, LQDR, routingToken, reserveToken);
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'SpookySwapStrategy', address, tx };
          }
        }
      }
    }

    {
      // xBOO SpookySwap strategies (reward varies)
      const addresses = [
        // 32 - stkxBOOv3
        [32, '0x30463d33735677B4E70f956e3dd61c6e94D70DFe', WFTM, BOO, XBOO_ACELAB],
      ];
      for (const [pid, address, routingToken, reserveToken, aceLab] of addresses) {
        const amount1 = await getTokenBalance(privateKey, network, BEFTM, address);
        const amount2 = await getPendingBalanceAceLab(privateKey, network, aceLab, pid, address);
        const MINIMUM_AMOUNT = 40000000000000000000n; // 40 beFTM
        if (BigInt(amount1) + BigInt(amount2) >= MINIMUM_AMOUNT) {
          await fixTwap(privateKey, network, address, SPO_EXCHANGE, BEFTM, routingToken, reserveToken);
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'SpookySwapStrategy', address, tx };
          }
        }
      }
    }

    {
      // BOO SpookySwap strategies
      const addresses = [
        // 0 - stkFTM/BOOv3
        [0, '0xaebd31E9FFcB222feE947f22369257cEcf1F96CA', BOO, SPO_FTM_BOO, BOO_MASTERCHEF_V1],
      ];
      for (const [pid, address, routingToken, reserveToken, masterChef] of addresses) {
        const amount1 = await getTokenBalance(privateKey, network, BOO, address);
        const amount2 = await getPendingBalanceBoo(privateKey, network, masterChef, pid, address);
        const MINIMUM_AMOUNT = 10000000000000000000n; // 10 BOO
        if (BigInt(amount1) + BigInt(amount2) >= MINIMUM_AMOUNT) {
          await fixTwap(privateKey, network, address, SPO_EXCHANGE, BOO, routingToken, reserveToken);
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'SpookySwapStrategy', address, tx };
          }
        }
      }
    }

    {
      // DEUS SpookySwap strategies
      const addresses = [
        // 1 - stkUSDC/DEIv3
        [1, '0x1DE2bC09527Aa3F6a3Aa35271471966b2dd4E215', USDC, SPO_USDC_DEI, BOO_MASTERCHEF_V2],
        // 2 - stkFTM/DEUSv3
        [2, '0xDE98dFbFCa4Bce256AF0b9Aa7664051a6B414548', DEUS, SPO_FTM_DEUS, BOO_MASTERCHEF_V2],
      ];
      for (const [pid, address, routingToken, reserveToken, masterChef] of addresses) {
        const amount1 = await getTokenBalance(privateKey, network, DEUS, address);
        const amount2 = await getPendingBalanceDeus(privateKey, network, masterChef, pid, address);
        const MINIMUM_AMOUNT = 1000000000000000000n; // 1 DEUS
        if (BigInt(amount1) + BigInt(amount2) >= MINIMUM_AMOUNT) {
          await fixTwap(privateKey, network, address, SPO_EXCHANGE, DEUS, routingToken, reserveToken);
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'SpookySwapStrategy', address, tx };
          }
        }
      }
    }

    {
      // PGK => USDC adapter
      const address = '0x40d0AA6FeC07A5B0770b6A4f34c8C69e93249668';
      const amount = await getTokenBalance(privateKey, network, PGK, address);
      const MINIMUM_AMOUNT = 500000000000000000000n; // 500 PGK
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'PGK', type: 'SpookySwapAdapter', address, tx };
        }
      }
    }

    {
      // beFTM => USDC adapter
      const address = '0x3023Cb7F9E4bB79c869B3B25248F1d85903c443F';
      const amount = await getTokenBalance(privateKey, network, BEFTM, address);
      const MINIMUM_AMOUNT = 25000000000000000000n; // 25 BEFTM
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'beFTM', type: 'SpookySwapAdapter', address, tx };
        }
      }
    }

    {
      // BOO => USDC adapter
      const address = '0x855aba982505d8C702dCFaB3e957A998b10D8049';
      const amount = await getTokenBalance(privateKey, network, BOO, address);
      const MINIMUM_AMOUNT = 10000000000000000000n; // 10 BOO
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'BOO', type: 'SpookySwapAdapter', address, tx };
        }
      }
    }

    {
      // DEUS => USDC adapter
      const address = '0x744ed0c7453b4332885e650cE66611cEd9f6e50b';
      const amount = await getTokenBalance(privateKey, network, DEUS, address);
      const MINIMUM_AMOUNT = 1000000000000000000n; // 1 DEUS
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'DEUS', type: 'SpookySwapAdapter', address, tx };
        }
      }
    }

    {
      // stkUSDLPv3 GEIST/CRV/WFTM adapter
      const address = '0xB307521B7e740afbC2993a9023430Df8F4915f58';
      const amount1 = await getTokenBalance(privateKey, network, GEIST, address);
      const amount2 = await getTokenBalance(privateKey, network, CRV, address);
      const amount3 = await getTokenBalance(privateKey, network, WFTM, address);
      const MINIMUM_AMOUNT1 = 6500000000000000000000n; // 6500 GEIST
      const MINIMUM_AMOUNT2 = 500000000000000000000n; // 500 CRV
      const MINIMUM_AMOUNT3 = 1000000000000000000000n; // 1000 WFTM
      if (BigInt(amount1) >= MINIMUM_AMOUNT1 || BigInt(amount2) >= MINIMUM_AMOUNT2 || BigInt(amount3) >= MINIMUM_AMOUNT3) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'GEIST+CRV+WAVAX', type: 'LiquidDriverCurveAdapter', address, tx };
        }
      }
    }

    {
      // PSM INJECTOR stkUSDLPv3 using USDC
      const address = '0x2Ff5b0df069E36da2f0c7E1AC381511ede792F82';
      const amount = await getTokenBalance(privateKey, network, USDC, address);
      const MINIMUM_AMOUNT = 5000000000n; // 5000 USDC
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'stkUSDLPv3', type: 'PsmInjector', address, tx };
        }
      }
    }

    {
      // cLQDR EXTENSION
      const address = '0x30d1900306FD84EcFBCb16F821Aba69054aca15C';
      const tx = await safeCollect(privateKey, network, address, false);
      if (tx !== null) {
        return { name: 'cLQDR', type: 'Extension', address, tx };
      }
    }

    /*
    {
      // cLQDR RECEIVER (obsolete)
      const address = '0x6f1c4303bC40AEee0aa60dD90e4eeC353487b66f';
      //const amount = await getTokenBalance(privateKey, network, LQDR, address);
      //const MINIMUM_AMOUNT = 20000000000000000000n; // 20 LQDR
      //if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address, false);
        if (tx !== null) {
          return { name: 'cLQDR', type: 'Buyback', address, tx };
        }
      //}
    }
    */

    {
      // cLQDR RECEIVER
      const address = '0xCD3563CD8dE2602701d5d9f960db30710fcc4053';
      //const amount = await getTokenBalance(privateKey, network, LQDR, address);
      //const MINIMUM_AMOUNT = 20000000000000000000n; // 20 LQDR
      //if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address, false);
        if (tx !== null) {
          return { name: 'cLQDR', type: 'Buyback', address, tx };
        }
      //}
    }

    {
      // MRA [Fantom]
      const address = '0xD51fd17f7d5B4C4486257bad5553dB3689F9FCe2';
      const flag =  await unallocated(privateKey, network, address);
      if (flag) {
        const tx = await safeAllocate(privateKey, network, address);
        if (tx !== null) {
          return { name: 'GRO+cLQDR', type: 'MultiRewardAllocator', address, tx };
        }
      }
    }

    {
      // MOR/bb-yv-USD AMO [Fantom]
      const address = '0x53AAF3c5FC977E2ED7E0e746306Dec3927829AE5';
      const amount =  await estimate(privateKey, network, address);
      if (BigInt(amount) > 0n) {
        const tx = await safeCollect(privateKey, network, address);
        if (tx !== null) {
          return { name: 'BEETS', type: 'BeethovenxStablePhantomPoolDssAmo0', address, tx };
        }
      }
      const flag =  await unbalanced(privateKey, network, address);
      if (flag) {
        const tx = await safeRebalance(privateKey, network, address);
        if (tx !== null) {
          return { name: 'MOR+bb-yv-USD', type: 'BeethovenxStablePhantomPoolDssAmo0', address, tx };
        }
      }
    }

    {
      // Payroll [Fantom]
      const address = '0x7AA3136a31Dd238E1413294a8b89689f97073625';
      const flag =  await unallocated(privateKey, network, address);
      if (flag) {
        const tx = await safeAllocate(privateKey, network, address);
        if (tx !== null) {
          return { name: 'GRO', type: 'Payroll', address, tx };
        }
      }
    }

    return false;
  }

  if (network === 'avaxmain') {

    const WHEAT = '0x1A51686Fb42861AA7E38c1CF8868877F43F82aA4';
    const WHEAT_MASTERCHEF = '0x5818388B1d756090FF1545D943fF9D1F6Ea13ce3';
    const JOE = '0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd';
    const JOE_MASTERCHEF_V2 = '0xd6a4F121CA35509aF06A0Be99093d08462f53052';
    const JOE_MASTERCHEF_V3 = '0x188bED1968b795d5c9022F6a0bb5931Ac4c18F00';
    const WAVAX = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';
    const WETH = '0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB';
    const WBTC = '0x50b7545627a5162F82A992c33b87aDc75187B218';
    const USDC = '0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664';
    const XJOE = '0x57319d41F71E81F3c65F2a47CA4e001EbAFd4F33';
    const CRV = '0x47536F17F4fF30e64A96a7555826b8f9e66ec468';
    const JOE_EXCHANGE = '0xB85B290B99B10dCd78189317b5bF965854bdc952';
    const TDJ_AVAX_JOE = '0x454E67025631C065d3cFAD6d71E6892f74487a15';
    const TDJ_AVAX_WETH = '0xFE15c2695F1F920da45C30AAE47d11dE51007AF9';
    const TDJ_AVAX_WBTC = '0xd5a37dC5C9A396A03dd1136Fc76A1a02B1c88Ffa';
    const TDJ_AVAX_DAI = '0x87Dee1cC9FFd464B79e058ba20387c1984aed86a';
    const TDJ_AVAX_USDC = '0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1';
    const TDJ_AVAX_USDT = '0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256';
    const TDJ_AVAX_LINK = '0x6F3a0C89f611Ef5dC9d96650324ac633D02265D3';
    const TDJ_AVAX_MIM = '0x781655d802670bbA3c89aeBaaEa59D3182fD755D';
    const TDJ_USDC_JOE = '0x67926d973cD8eE876aD210fAaf7DFfA99E414aCf';
    const TDJ_USDT_JOE = '0x1643de2efB8e35374D796297a9f95f64C082a8ce';
    const stkUSDCv3 = '0xdC4D358B34619e4fE7feb28bE301B2FBe4F3aFf9';

    {
      // JOE strategies
      const addresses = [
        // 24 - xJOE
        [24, '0x2E53F47a807F0c45c61C899e62504336B0b5dBDf', JOE, XJOE, JOE_MASTERCHEF_V2],
        // 0 - stkAVAX/JOEv3
        [0, '0x04abDB55DCd0167BFcE8FA0fA125F102c4734C62', JOE, TDJ_AVAX_JOE, JOE_MASTERCHEF_V3],
        // 26 - stkAVAX/WETHv3
        [26, '0xE70aA236f2c2dABC346e193F606986Bb843bA3d9', WAVAX, TDJ_AVAX_WETH, JOE_MASTERCHEF_V2],
        // 27 - stkAVAX/WBTCv3
        [27, '0xeB8e1c316694742E7042882be1ac55ebbD2bCEbB', WAVAX, TDJ_AVAX_WBTC, JOE_MASTERCHEF_V2],
        // 37 - stkAVAX/DAIv3
        [37, '0xe46a3E475dd4D18A7D2A009b7FA1B113f2bd2903', WAVAX, TDJ_AVAX_DAI, JOE_MASTERCHEF_V2],
        // 39 - stkAVAX/USDCv3
        [39, '0xed98897f99F0Bb8732afF727f3DBD01bA95D25b4', WAVAX, TDJ_AVAX_USDC, JOE_MASTERCHEF_V2],
        // 28 - stkAVAX/USDTv3
        [28, '0x38fBF8e6ADbfa44072688BeBd921Fdc6b4b6f328', WAVAX, TDJ_AVAX_USDT, JOE_MASTERCHEF_V2],
        // 29 - stkAVAX/LINKv3
        [29, '0x235B1E29dc44bA33d0A6518a62A998bCFd8D62e9', WAVAX, TDJ_AVAX_LINK, JOE_MASTERCHEF_V2],
        // 43 - stkAVAX/MIMv3
        [43, '0xAFe0d419658dEbEF3f8eDc23b011877770594360', WAVAX, TDJ_AVAX_MIM, JOE_MASTERCHEF_V2],
        // 58 - stkUSDC/JOEv3
        [58, '0x0A0E72c79b5559B9266deD694bccf91d7C60c300', JOE, TDJ_USDC_JOE, JOE_MASTERCHEF_V2],
        // 30 - stkUSDT/JOEv3
        [30, '0x731010369d41147523e6ae65aD3dB4Dea1Eb13ff', JOE, TDJ_USDT_JOE, JOE_MASTERCHEF_V2],
      ];
      for (const [pid, address, routingToken, reserveToken, masterChef] of addresses) {
        const amount1 = await getTokenBalance(privateKey, network, JOE, address);
        const amount2 = await getPendingBalanceJoe(privateKey, network, masterChef, pid, address);
        const MINIMUM_AMOUNT = 250000000000000000000n; // 250 JOE
        if (BigInt(amount1) + BigInt(amount2) >= MINIMUM_AMOUNT) {
          await fixTwap(privateKey, network, address, JOE_EXCHANGE, JOE, routingToken, reserveToken);
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'TraderJoeStrategy', address, tx };
          }
        }
      }
    }

    /*
    {
      // WHEAT strategies
      const addresses = [
        // 0 - stkWHEATv3
        [0, '0x01d1c4eC99D0A7D8f4141D42D1624fffa054D7Ae', WHEAT, WHEAT],
      ];
      for (const [pid, address, routingToken, reserveToken] of addresses) {
        const amount1 = await getTokenBalance(privateKey, network, WHEAT, address);
        const amount2 = await getPendingBalance(privateKey, network, WHEAT_MASTERCHEF, pid, address);
        const MINIMUM_AMOUNT = 1000000000000000000000n; // 1000 WHEAT
        if (BigInt(amount1) + BigInt(amount2) >= MINIMUM_AMOUNT) {
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'WheatStrategy', address, tx };
          }
        }
      }
    }
    */

    {
      // JOE SPLITTING ADAPTER
      const address = '0x67E5830CCef2Dc38aebEf4eC7D06baD5b5957D44';
      const amount = await getTokenBalance(privateKey, network, JOE, address);
      const MINIMUM_AMOUNT = 1000000000000000000000n; // 1000 JOE
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'JOE', type: 'SplittingAdapter', address, tx };
        }
      }
    }

    {
      // PSM INJECTOR stkUSDCv3
      const address = '0x5622C4A8F6B245aFdddA6c32748055837A2616Cc';
      const amount = await getTokenBalance(privateKey, network, stkUSDCv3, address);
      const MINIMUM_AMOUNT = 5000000000n; // 5000 stkUSDCv3
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'stkUSDCv3', type: 'PsmInjector', address, tx };
        }
      }
    }

    {
      // PSM INJECTOR stkUSDLPv3 using USDC
      const address = '0x4EcD4082C1E809D89901cD3A802409c8d2Ae6EC4';
      const amount = await getTokenBalance(privateKey, network, USDC, address);
      const MINIMUM_AMOUNT = 5000000000n; // 5000 USDC
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'stkUSDLPv3', type: 'PsmInjector', address, tx };
        }
      }
    }

    {
      // stkUSDLPv3 CRV/WAVAX adapter
      const address = '0x744ed0c7453b4332885e650cE66611cEd9f6e50b';
      const amount1 = await getTokenBalance(privateKey, network, CRV, address);
      const amount2 = await getTokenBalance(privateKey, network, WAVAX, address);
      const MINIMUM_AMOUNT1 = 500000000000000000000n; // 500 CRV
      const MINIMUM_AMOUNT2 = 25000000000000000000n; // 25 WAVAX
      if (BigInt(amount1) >= MINIMUM_AMOUNT1 || BigInt(amount2) >= MINIMUM_AMOUNT2) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'CRV+WAVAX', type: 'TraderJoeCurveAdapter', address, tx };
        }
      }
    }

    {
      // AVAX/JOE collector
      const address = '0xa6E48716e4426ba51C2459c890aDd6604f96404F';
      const amount = await getTokenBalance(privateKey, network, TDJ_AVAX_JOE, address);
      const MINIMUM_AMOUNT = 100000000000000000000n; // 100 AVAX/JOE
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'AVAX/JOE', type: 'TraderJoeCollector', address, tx };
        }
      }
    }

    {
      // WAVAX collector
      const address = '0xa8FDF216A180A798ED783e14EE71557E613C52bf';
      const amount = await getTokenBalance(privateKey, network, WAVAX, address);
      const MINIMUM_AMOUNT = 25000000000000000000n; // 25 WAVAX
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'WAVAX', type: 'TraderJoeCollector', address, tx };
        }
      }
    }

    {
      // WETH collector
      const address = '0x42C03f6d6c00f0D5603080a3475903195e9F6CEc';
      const amount = await getTokenBalance(privateKey, network, WETH, address);
      const MINIMUM_AMOUNT = 500000000000000000n; // 0.5 WETH
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'WETH', type: 'TraderJoeCollector', address, tx };
        }
      }
    }

    {
      // WBTC collector
      const address = '0xCfc7E18096C96Bf33203CCc2781E1D1f8fe77Ceb';
      const amount = await getTokenBalance(privateKey, network, WBTC, address);
      const MINIMUM_AMOUNT = 50000000000000000n; // 0.05 WBTC
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'WBTC', type: 'TraderJoeCollector', address, tx };
        }
      }
    }

    /* TODO reroute rewards to multisig
    {
      // JOE buyback
      const address = '0xae35A19F1DAc62AD3794773D5f0983f05073D0f2';
      const amount = await getTokenBalance(privateKey, network, JOE, address);
      const MINIMUM_AMOUNT = 250000000000000000000n; // 250 JOE
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'JOE', type: 'TraderJoeBuyback', address, tx };
        }
      }
    }
    */

    {
      // MRA [Avalanche]
      const address = '0x6adf0cd8BE6b8cF7149C443dA8D4F7Ca942EB9B5';
      const flag =  await unallocated(privateKey, network, address);
      if (flag) {
        const tx = await safeAllocate(privateKey, network, address);
        if (tx !== null) {
          return { name: 'GRO', type: 'MultiRewardAllocator', address, tx };
        }
      }
    }

    return false;
  }

  if (network === 'bscmain') {

    // NEW SYSTEM v3
    const CAKE = '0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82';
    const CAKE_MASTERCHEF = '0x73feaa1eE314F8c655E354234017bE2193C9E24E';
    const CAKE_EXCHANGE = '0xf31366e709C8d75BCC6e3Bc172E46831D6A4C2B3';
    const BANANA = '0x603c7f932ED1fc6575303D8Fb018fDCBb0f39a95';
    const BANANA_MASTERCHEF = '0x5c8D727b265DBAfaba67E050f2f739cAeEB4A6F9';
    const BANANA_EXCHANGE = '0x39c54945C9B880d4B5F15b0BA3c8c17226C37d68';
    const WHEAT = '0x3ab63309F85df5D4c3351ff8EACb87980E05Da4E';
    const WHEAT_MASTERCHEF = '0x95fABAe2E9Fb0A269cE307550cAC3093A3cdB448';
    const BNB = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c';
    const ETH = '0x2170Ed0880ac9A755fd29B2688956BD959F933F8';
    const BUSD = '0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56';
    const USDT = '0x55d398326f99059fF775485246999027B3197955';
    const PCS_BNB_CAKE = '0x0eD7e52944161450477ee417DE9Cd3a859b14fD0';
    const PCS_BNB_BUSD = '0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16';
    const PCS_BUSD_USDT = '0x7EFaEf62fDdCCa950418312c6C91Aef321375A00';
    const PCS_BNB_ETH = '0x74E4716E431f45807DCF19f284c7aA99F18a4fbc';
    const PCS_BNB_BTCB = '0x61EB789d75A95CAa3fF50ed7E47b96c132fEc082';
    const PCS_BNB_USDT = '0x16b9a82891338f9bA80E2D6970FddA79D1eb0daE';
    const PCS_BUSD_USDC = '0x2354ef4DF11afacb85a5C7f98B624072ECcddbB1';
    const PCS_BUSD_BTCB = '0xF45cd219aEF8618A92BAa7aD848364a158a24F33';
    const PCS_BUSD_CAKE = '0x804678fa97d91B974ec2af3c843270886528a9E6';
    const PCS_ETH_BTCB = '0xD171B26E4484402de70e3Ea256bE5A2630d7e88D';
    const PCS_ETH_USDC = '0xEa26B78255Df2bBC31C1eBf60010D78670185bD0';
    const PCS_USDT_CAKE = '0xA39Af17CE4a8eb807E076805Da1e2B8EA7D0755b';
    const PCS_USDT_USDC = '0xEc6557348085Aa57C72514D67070dC863C0a5A8c';
    const APE_MOR_BUSD = '0x33526eD690200663EAAbF28e1D8621e58898c5fd';

    {
      // CAKE strategies
      const addresses = [
        // 0 - stkCAKEv3
        [0, '0xB50Acf6195F97177D33D132A3E5617b934C351d3', CAKE, CAKE],
        // 251 - stkBNB/CAKEv3
        [251, '0xd8C76eF0de11f9cc9708EB966A87e25a7E6C7949', CAKE, PCS_BNB_CAKE],
        // 252 - stkBNB/BUSDv3
        [252, '0x0170D4C58AD9A9D8ab031c0270353d7034B87f6F', BNB, PCS_BNB_BUSD],
        // 258 - stkBUSD/USDTv3
        [258, '0xd7A45F561189529de5975d522F0B5d7D4bfC94de', BUSD, PCS_BUSD_USDT],
        // 261 - stkBNB/ETHv3
        [261, '0xE487a3780D56F2ECD142201907dF16350bb09946', BNB, PCS_BNB_ETH],
        // 262 - stkBNB/BTCBv3
        [262, '0x9Df7B409925cc93dE1BB4ADDfA9Aed2bcE913F08', BNB, PCS_BNB_BTCB],
        // 264 - stkBNB/USDTv3
        [264, '0x839289A22604857A9BdB3231d37Af569ACD8A3fe', BNB, PCS_BNB_USDT],
        // 283 - stkBUSD/USDCv3
        [283, '0x60CD286AF05A3e096C8Ace193950CffA5E8e3CE0', BUSD, PCS_BUSD_USDC],
        // 365 - stkBUSD/BTCBv3
        [365, '0x26E0701F5881161043d56eb3Ddfde0b8c6772060', BUSD, PCS_BUSD_BTCB],
        // 389 - stkBUSD/CAKEv3
        [389, '0xFA6388B7980126C2d7d0c5FC02949a2fF40F95DE', CAKE, PCS_BUSD_CAKE],
        // 408 - stkETH/BTCBv3
        [408, '0x9FDD69a473d2216c5D232510DDF2328272bC6847', ETH, PCS_ETH_BTCB],
        // 409 - stkETH/USDCv3
        [409, '0xcAD2E1b2257795f0D580d49520741E93654fAaB5', ETH, PCS_ETH_USDC],
        // 422 - stkUSDT/CAKEv3
        [422, '0xC0c8C554069d85166B834b2Cb3541d66f53DC4f5', CAKE, PCS_USDT_CAKE],
        // 423 - stkUSDT/USDCv3
        [423, '0x01A50D26b9B40c92fa40CBC698DeB57c65b4B7e4', USDT, PCS_USDT_USDC],
      ];
      for (const [pid, address, routingToken, reserveToken] of addresses) {
        const amount1 = await getTokenBalance(privateKey, network, CAKE, address);
        const amount2 = await getPendingBalance(privateKey, network, CAKE_MASTERCHEF, pid, address);
        const MINIMUM_AMOUNT = 50000000000000000000n; // 50 CAKE
        if (BigInt(amount1) + BigInt(amount2) >= MINIMUM_AMOUNT) {
          await fixTwap(privateKey, network, address, CAKE_EXCHANGE, CAKE, routingToken, reserveToken);
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'PancakeSwapStrategy', address, tx };
          }
        }
      }
    }

    {
      // BANANA strategies
      const addresses = [
        // 0 - stkBANANAv3
        [0, '0x13e7A6691FE00DE975CF27868386f4aE9aed3cdC', BANANA, BANANA],
        // 115 - stkMOR/BUSDv3
        [115, '0xC2E8C3c427E0a5BaaF512A013516aECB65Bd75CB', BUSD, APE_MOR_BUSD],
        // 115 - stkMOR/BUSDv3
        [115, '0xC8216C4ac63F3cAC4f7e74A82d2252B7658FA8b1', BUSD, APE_MOR_BUSD],
      ];
      for (const [pid, address, routingToken, reserveToken] of addresses) {
        const amount1 = await getTokenBalance(privateKey, network, BANANA, address);
        const amount2 = await getPendingBalance(privateKey, network, BANANA_MASTERCHEF, pid, address);
        const MINIMUM_AMOUNT = 500000000000000000000n; // 500 BANANA
        if (BigInt(amount1) + BigInt(amount2) >= MINIMUM_AMOUNT) {
          await fixTwap(privateKey, network, address, BANANA_EXCHANGE, BANANA, routingToken, reserveToken);
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'ApeSwapStrategy', address, tx };
          }
        }
      }
    }

    /*
    {
      // WHEAT strategies
      const addresses = [
        // 0 - stkWHEATv3
        [0, '0x5a6D9e05C0Da125a2FB67a68ab5D427dA4629590', WHEAT, WHEAT],
      ];
      for (const [pid, address, routingToken, reserveToken] of addresses) {
        const amount1 = await getTokenBalance(privateKey, network, WHEAT, address);
        const amount2 = await getPendingBalance(privateKey, network, WHEAT_MASTERCHEF, pid, address);
        const MINIMUM_AMOUNT = 1000000000000000000000n; // 1000 WHEAT
        if (BigInt(amount1) + BigInt(amount2) >= MINIMUM_AMOUNT) {
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'WheatStrategy', address, tx };
          }
        }
      }
    }
    */

    {
      // CAKE collector
      const address = '0x3C8337B4011bdbEfB41FACEdA52923099db4aAd8';
      const amount = await getTokenBalance(privateKey, network, CAKE, address);
      const MINIMUM_AMOUNT = 50000000000000000000n; // 50 CAKE
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'CAKE', type: 'PancakeSwapCollector', address, tx };
        }
      }
    }

    {
      // BANANA collector
      const address = '0xe13e62830D300C6Fa64287F7dDEf3af6894B4868';
      const amount = await getTokenBalance(privateKey, network, BANANA, address);
      const MINIMUM_AMOUNT = 500000000000000000000n; // 500 BANANA
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'BANANA', type: 'ApeSwapCollector', address, tx };
        }
      }
    }

    /* TODO reroute rewards to multisig
    {
      // CAKE buyback
      const address = '0xcD22272873B681986cE984E719D22A790dfE9C4a';
      const amount = await getTokenBalance(privateKey, network, CAKE, address);
      const MINIMUM_AMOUNT = 50000000000000000000n; // 50 CAKE
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'CAKE', type: 'PancakeSwapBuyback', address, tx };
        }
      }
    }
    */

    /* TODO reroute rewards to multisig
    {
      // BANANA buyback
      const address = '0x889c56ABcc2606e77B3733E8703E9e040655b8E5';
      const amount = await getTokenBalance(privateKey, network, BANANA, address);
      const MINIMUM_AMOUNT = 500000000000000000000n; // 500 BANANA
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'BANANA', type: 'ApeSwapBuyback', address, tx };
        }
      }
    }
    */

    // OLD SYSTEM v2

    {
      // 5 - stkCAKE
      const address = '0x84BA65DB2da175051E25F86e2f459C863CBb3E0C';
      const amount = await pendingReward(privateKey, network, address);
      const MINIMUM_AMOUNT = 50000000000000000000n; // 50 CAKE
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          const name = await getTokenSymbol(privateKey, network, address);
          return { name, type: 'PancakeStrategy', address, tx };
        }
      }
    }

    {
      // AUTO strategies
      const addresses = [
        // 33 - stkBNB/CAKEv2
        '0x86c15Efe94320Cd139eA4875b7ceF336e1F91f16',
        // 34 - stkBNB/BUSDv2
        '0xd5ffd8318b1c82FDE321f7BC1a553462A13A2E14',
        // 35 - stkBNB/USDTv2
        '0x7259CeBc6D8f84afdce4B81a3a33D53A526521F8',
        // 36 - stkBNB/BTCBv2
        '0x074fD0f3289cF3F5E0E80c969F62B21cB38Ad3b5',
        // 37 - stkBNB/ETHv2
        '0x15B310c8D9d0Ac9aefB94BF492e7eAbC43B4f93e',
        // 38 - stkBUSD/USDTv2
        '0x6f1c4303bC40AEee0aa60dD90e4eeC353487b66f',
        // 39 - stkBUSD/VAIv2
        '0xC8daDd57BD9342b7ba9449B952DBE11B4f3D1648',
        // 40 - stkBNB/DOTv2
        '0x5C96941B28B824c3E9d01E5cb2D77B3f7801560e',
        // 41 - stkBNB/LINKv2
        '0x501382584a3DBF1471918Cd4ee0fd3bE23FfDF29',
        // 42 - stkBNB/UNIv2
        '0x0900a05910E7d4811f9FC17843120D6412df2968',
        // 43 - stkBNB/DODOv2
        '0x67A4c8d130ED95fFaB9F2CDf001811Ada1077875',
        // 44 - stkBNB/ALPHAv2
        '0x6C6d105066462EE9b5Cfc7628e2edB1000e887F1',
        // 45 - stkBNB/ADAv2
        '0x73099318dfBB1C59e473322F29C215132A14Ab86',
        // 46 - stkBUSD/USTv2
        '0xB2b5dba919Da2E06d6cDd15dF17bA4b99D3eB1bD',
        // 47 - stkBUSD/BTCBv2
        '0xf30D01da4257c696e537E2fdF0a2Ce6C9D627352',
        // 48 - stkbeltBNBv2
        '0xeC97D2e53e34Aa8E5C6a843D9cd74641E645681A',
        // 49 - stkbeltBTCv2
        '0x04abDB55DCd0167BFcE8FA0fA125F102c4734C62',
        // 50 - stkbeltETHv2
        '0xE70aA236f2c2dABC346e193F606986Bb843bA3d9',
        // 51 - stk4BELTv2
        '0xeB8e1c316694742E7042882be1ac55ebbD2bCEbB',
      ];
      for (const address of addresses) {
        const fee = await performanceFee(privateKey, network, address);
        const feeAmount = await pendingPerformanceFee(privateKey, network, address);
        const MINIMUM_AMOUNT = 1000000000000000000n; // 1 AUTO
        if (BigInt(feeAmount) * 1000000000000000000n / BigInt(fee) >= MINIMUM_AMOUNT) {
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'AutoFarmStrategy', address, tx };
          }
        }
      }
    }

  /*
    {
      // PANTHER strategies
      const addresses = [
        // - stkBNB/BUSDv2
        '0x4046492479a5bA18c2a947A1db75f4f1ef227BF1',
        // - stkBNB/BTCBv2
        '0xc1d3F1dB60DE17afD7770464BAb05c58129d7Ee0',
        // - stkBNB/ETHv2
        '0x9C009595F330CA8070e78b889183e7b8a96cB962',
        // - stkBNB/CAKEv2
        '0x1f48dCbCE7fC91180492a7b083472924b4e8a44b',
        // - stkBUSD/USDCv2
        '0xd802621F65Bd96D76e84E49EecdED49C5acb105d',
        // - stkBNB/USDTv2
        '0xE0327dA3f94Efe600569Ca68Aa02e6921FD89Bfa',
        // - stkBNB/PANTHERv2
        '0x358582CEeeB0F008495C06206973F5F6e495accd',
        // - stkBUSD/PANTHERv2
        '0x1A51686Fb42861AA7E38c1CF8868877F43F82aA4',
      ];
      for (const address of addresses) {
        const fee = await performanceFee(privateKey, network, address);
        const feeAmount = await pendingPerformanceFee(privateKey, network, address);
        const MINIMUM_AMOUNT = 6000000000000000000000n; // 6000 PANTHER
        if (BigInt(feeAmount) * 1000000000000000000n / BigInt(fee) >= MINIMUM_AMOUNT) {
          const tx = await safeGulp(privateKey, network, address);
          if (tx !== null) {
            const name = await getTokenSymbol(privateKey, network, address);
            return { name, type: 'PantherStrategy', address, tx };
          }
        }
      }
    }
  */

    {
      // CAKE collector
      const address = '0x14bAc5f216337F8da5f41Bb920514Af98ef62c36';
      const amount = await pendingReward(privateKey, network, address);
      const MINIMUM_AMOUNT = 50000000000000000000n; // 50 CAKE
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'CAKE', type: 'PancakeCollector', address, tx };
        }
      }
    }

    {
      // AUTO/CAKE collector adapter
      const address = '0x626E98ef225A6f79523C9004E8731B793dfd0F68';
      const amount = await pendingSource(privateKey, network, address);
      const MINIMUM_AMOUNT = 1000000000000000000n; // 1 AUTO
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'AUTO/CAKE', type: 'AutoFarmCollectorAdapter', address, tx };
        }
      }
    }

  /*
    {
      // PANTHER buyback adapter
      const address = '0x495089390569d47807F1Db83F14e053002DB25b4';
      const amount = await pendingSource(privateKey, network, address);
      const MINIMUM_AMOUNT = 2000000000000000000000n; // 2000 PANTHER
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'PANTHER/BNB', type: 'PantherBuybackAdapter', address, tx };
        }
      }
    }
  */

    /* TODO reroute rewards to multisig
    {
      // CAKE buyback
      const address = '0xC351706C3212D45fc24F6B89e686f07fAb048b16';
      const amount = await pendingBuyback(privateKey, network, address);
      const MINIMUM_AMOUNT = 50000000000000000000n; // 50 CAKE
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'CAKE', type: 'PancakeBuyback', address, tx };
        }
      }
    }
    */

    /* TODO reroute rewards to multisig
    {
      // universal buyback
      const address = '0x01d1c4eC99D0A7D8f4141D42D1624fffa054D7Ae';
      const amount = await pendingBuyback(privateKey, network, address);
      const MINIMUM_AMOUNT = 1000000000000000000n; // 1 BNB
      if (BigInt(amount) >= MINIMUM_AMOUNT) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          return { name: 'BNB', type: 'UniversalBuyback', address, tx };
        }
      }
    }
    */

    {
      // MRA [BSC]
      const address = '0x07c3c8350b341179582CA5e6C4BF04fEC5Cf5392';
      const flag = await unallocated(privateKey, network, address);
      if (flag) {
        const tx = await safeAllocate(privateKey, network, address);
        if (tx !== null) {
          return { name: 'GRO', type: 'MultiRewardAllocator', address, tx };
        }
      }
    }

    return false;
  }

/*
  const length = await poolLength(privateKey, network);

  for (let pid = 0; pid < length; pid++) {
    if (!ACTIVE_PIDS.includes(pid)) continue;
    const strategy = await readStrategy(privateKey, network, pid);
    const [reward, fee] = await Promise.all([
      pendingReward(privateKey, network, strategy),
      pendingPerformanceFee(privateKey, network, strategy),
    ]);
    if (BigInt(reward) > 0n || BigInt(fee) > 0n) {
      const tx = await safeGulp(privateKey, network, strategy);
      if (tx !== null) {
        const symbol = await getTokenSymbol(privateKey, network, strategy);
        return { name: symbol, type: 'Strategy', address: strategy, tx };
      }
    }
  }

  for (let pid = 0; pid < length; pid++) {
    if (!ACTIVE_PIDS.includes(pid)) continue;
    const strategy = await readStrategy(privateKey, network, pid);
    const collector = await readCollector(privateKey, network, strategy);
    let deposit, reward;
    try {
      [deposit, reward] = await Promise.all([
        pendingDeposit(privateKey, network, collector),
        pendingReward(privateKey, network, collector),
      ]);
    } catch {
      try {
        [deposit, reward] = await Promise.all([
          pendingSource(privateKey, network, collector),
          pendingTarget(privateKey, network, collector),
        ]);
      } catch {
        [deposit, reward] = [1, 1];
      }
    }
    if (BigInt(deposit) > 0n || BigInt(reward) > 0n) {
      const tx = await safeGulp(privateKey, network, collector);
      if (tx !== null) {
        const symbol = await getTokenSymbol(privateKey, network, strategy);
        return { name: symbol, type: 'FeeCollector', address: collector, tx };
      }
    }
  }

  for (let pid = 0; pid < length; pid++) {
    if (!ACTIVE_PIDS.includes(pid)) continue;
    const strategy = await readStrategy(privateKey, network, pid);
    const collector = await readCollector(privateKey, network, strategy);
    let buyback;
    try {
      buyback = await readBuyback(privateKey, network, collector);
    } catch {
      continue;
    }
    const [reward] = await Promise.all([
      pendingBuyback(privateKey, network, buyback),
    ]);
    if (BigInt(reward) > 0n) {
      const tx = await safeGulp(privateKey, network, buyback);
      if (tx !== null) {
        const symbol = await getTokenSymbol(privateKey, network, strategy);
        return { name: symbol, type: 'Buyback', address: buyback, tx };
      }
    }
  }

  return false;
*/
}

async function reportError(e, type, detail) {
  const message = typeof e === 'object' && e !== null && 'message' in e ? e.message : String(e);
  if (message.includes('SERVER_ERROR')) return;
  if (message.includes('Gateway timeout')) return;
  if (message.includes('502 Bad Gateway')) return;
  if (message.includes('internal error')) return;
  if (message.includes('Unknown Error')) return;
  if (message.includes('ETIMEDOUT')) return;
  if (message.includes('ESOCKETTIMEDOUT')) return;
  if (message.includes('header not found')) return;
  if (message.includes('handle request error')) return;
  if (message.includes('Too Many Requests')) return;
  if (message.includes('Could not find block')) return;
  if (message.includes('cannot query unfinalized data')) return;
  if (message.includes('invalid argument 0: hex string without 0x prefix')) return;
  await sendTelegramMessage('<i>GulpBot (' + escapeHTML(detail) + ') ' + escapeHTML(type) + ' (' + escapeHTML(message) + ')</i>');
}

async function main(args) {
  let [binary, script, network] = args;
  network = network || 'bscmain';

  // handy to list all contracts
  // await listContracts(privateKey, network);
  // return;

  readLastGulp(network);

  await sendTelegramMessage('<i>GulpBot (' + network + ') Initiated</i>');

  let interrupted = false;
  interrupt(async (e) => {
    if (!interrupted) {
      interrupted = true;
      await reportError(e, 'Interrupted', network);
      exit();
    }
  });

  while (true) {
    await sleep(MONITORING_INTERVAL * 1000);

    try {
      const lines = [];
      const account = getDefaultAccount(privateKey, network);
      const accountUrl = ADDRESS_URL_PREFIX[network] + account;
      const value = await getNativeBalance(privateKey, network);
      const balance = Number(coins(value, 18)).toFixed(4);
      lines.push('<a href="' + accountUrl + '">GulpBot</a>');
      lines.push('<code>' + balance + ' ' + NATIVE_SYMBOL[network] + '</code>');
      const result = await gulpAll(privateKey, network);
      if (result === false) continue;
      const { name, type, address, tx } = result;
      const url = ADDRESS_URL_PREFIX[network] + address;
      const txUrl = TX_URL_PREFIX[network] + tx;
      const txPrefix = tx.substr(0, 6);
      lines.push('<a href="' + url + '">' + type + '</a>.gulp() at <a href="' + txUrl + '">' + txPrefix + '</a> for ' + name);
      await sendTelegramMessage(lines.join('\n'));
    } catch (e) {
      await reportError(e, 'Failure', network);
    }
  }
}

entrypoint(main);
