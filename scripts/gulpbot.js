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

const NETWORK_ID = {
  'bscmain': 56,
  'bsctest': 97,
};

const NETWORK_NAME = {
  56: 'bscmain',
  97: 'bsctest',
};

const ADDRESS_URL_PREFIX = {
  'bscmain': 'https://bscscan.com/address/',
  'bsctest': 'https://testnet.bscscan.com/address/',
};

const TX_URL_PREFIX = {
  'bscmain': 'https://bscscan.com/tx/',
  'bsctest': 'https://testnet.bscscan.com/tx/',
};

const NATIVE_SYMBOL = {
  'bscmain': 'BNB',
  'bsctest': 'BNB',
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
    'https://apis.ankr.com/' + ankrApikeyBscmain + '/' + ankrProjectId + '/binance/full/main',
  ],
  'bsctest': [
    'https://data-seed-prebsc-1-s1.binance.org:8545/',
    'https://data-seed-prebsc-2-s1.binance.org:8545/',
    'https://data-seed-prebsc-1-s2.binance.org:8545/',
    'https://data-seed-prebsc-2-s2.binance.org:8545/',
    'https://data-seed-prebsc-1-s3.binance.org:8545/',
    'https://data-seed-prebsc-2-s3.binance.org:8545/',
    'https://apis.ankr.com/' + ankrApikeyBsctest + '/' + ankrProjectId + '/binance/full/test',
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

let lastTelegramMessage = {};

async function sendTelegramMessage(message, key = '') {
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
}

// lib

const IERC20_ABI = require('../build/contracts/IERC20.json').abi;
const MASTERCHEF_ABI = require('../build/contracts/CustomMasterChef.json').abi;
const STRATEGY_ABI = require('../build/contracts/RewardCompoundingStrategyToken.json').abi;
const COLLECTOR_ADAPTER_ABI = require('../build/contracts/AutoFarmFeeCollectorAdapter.json').abi;
const COLLECTOR_ABI = require('../build/contracts/FeeCollector.json').abi;
const BUYBACK_ABI = require('../build/contracts/Buyback.json').abi;
const UNIVERSAL_BUYBACK_ABI = require('../build/contracts/UniversalBuyback.json').abi;

const MASTERCHEF_ADDRESS = {
  'bscmain': '0x95fABAe2E9Fb0A269cE307550cAC3093A3cdB448',
  'bsctest': '0xF4748df5D63F6AB01e276065E6bD098Ce8dEA98a',
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

async function gulp0(privateKey, network, address, nonce) {
  const web3 = getWeb3(privateKey, network);
  const abi = STRATEGY_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const [from] = web3.currentProvider.getAddresses();
  let txId = null;
  try {
    const estimatedGas = await contract.methods.gulp().estimateGas({ from, nonce });
    const gas = 2 * estimatedGas;
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

async function gulp1(privateKey, network, address, nonce) {
  const web3 = getWeb3(privateKey, network);
  const abi = COLLECTOR_ADAPTER_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const [from] = web3.currentProvider.getAddresses();
  let txId = null;
  try {
    const estimatedGas = await contract.methods.gulp('1').estimateGas({ from, nonce });
    const gas = 2 * estimatedGas;
    await contract.methods.gulp('1').send({ from, nonce, gas })
      .on('transactionHash', (hash) => {
        txId = hash;
      });
  } catch (e) {
    throw new Error(e.message);
  }
  if (txId === null) throw new Error('Failure reading txId');
  return txId;
}

async function gulp2(privateKey, network, address, nonce) {
  const web3 = getWeb3(privateKey, network);
  const abi = UNIVERSAL_BUYBACK_ABI;
  const contract = new web3.eth.Contract(abi, address);
  const [from] = web3.currentProvider.getAddresses();
  let txId = null;
  try {
    const estimatedGas = await contract.methods.gulp('1', '1').estimateGas({ from, nonce });
    const gas = 2 * estimatedGas;
    await contract.methods.gulp('1', '1').send({ from, nonce, gas })
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
const DEFAULT_GULP_INTERVAL = 12 * 60 * 60; // 12 hours
const GULP_INTERVAL = {
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
  '0x4046492479a5bA18c2a947A1db75f4f1ef227BF1': 48 * 60 * 60, // 48 hours
  // - stkBNB/BTCBv2
  '0xc1d3F1dB60DE17afD7770464BAb05c58129d7Ee0': 48 * 60 * 60, // 48 hours
  // - stkBNB/ETHv2
  '0x9C009595F330CA8070e78b889183e7b8a96cB962': 48 * 60 * 60, // 48 hours
  // - stkBNB/CAKEv2
  '0x1f48dCbCE7fC91180492a7b083472924b4e8a44b': 48 * 60 * 60, // 48 hours
  // - stkBUSD/USDCv2
  '0xd802621F65Bd96D76e84E49EecdED49C5acb105d': 48 * 60 * 60, // 48 hours
  // - stkBNB/USDTv2
  '0xE0327dA3f94Efe600569Ca68Aa02e6921FD89Bfa': 48 * 60 * 60, // 48 hours
  // - stkBNB/PANTHERv2
  '0x358582CEeeB0F008495C06206973F5F6e495accd': 48 * 60 * 60, // 48 hours
  // - stkBUSD/PANTHERv2
  '0x1A51686Fb42861AA7E38c1CF8868877F43F82aA4': 48 * 60 * 60, // 48 hours

  // CAKE collector
  '0x14bAc5f216337F8da5f41Bb920514Af98ef62c36': 24 * 60 * 60, // 24 hours
  // AUTO/CAKE collector adapter
  '0x626E98ef225A6f79523C9004E8731B793dfd0F68': 48 * 60 * 60, // 48 hours
  // CAKE buyback
  '0xC351706C3212D45fc24F6B89e686f07fAb048b16': 24 * 60 * 60, // 24 hours

  // PANTHER buyback adapter
  '0x495089390569d47807F1Db83F14e053002DB25b4': 48 * 60 * 60, // 48 hours
  // Universal buyback
  '0x139ee66ABc14889921d24dA7e60DdB03dc2E1bEE': 48 * 60 * 60, // 48 hours
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

function readLastGulp() {
  try { lastGulp = JSON.parse(fs.readFileSync('gulpbot.json')); } catch (e) { }
}

function writeLastGulp() {
  try { fs.writeFileSync('gulpbot.json', JSON.stringify(lastGulp, undefined, 2)); } catch (e) { }
}

async function safeGulp(privateKey, network, address) {
  const now = Date.now();
  const timestamp = lastGulp[address] || 0;
  const ellapsed = (now - timestamp) / 1000;
  const interval = GULP_INTERVAL[address] || DEFAULT_GULP_INTERVAL;
  if (ellapsed < interval) return null;
  const nonce = await getNonce(privateKey, network);
  try {
    try { const txId = await gulp0(privateKey, network, address, nonce); return txId; } catch { }
    try { const txId = await gulp1(privateKey, network, address, nonce); return txId; } catch { }
    const txId = await gulp2(privateKey, network, address, nonce);
    return txId;
  } finally {
    lastGulp[address] = now;
    writeLastGulp();
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

async function gulpAll(privateKey, network) {

  {
    // 5 - stkCAKE
    const address = '0x84BA65DB2da175051E25F86e2f459C863CBb3E0C';
    const amount = await pendingReward(privateKey, network, address);
    if (BigInt(amount) > 20000000000000000000n) { // 20 CAKE
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
      const amount = await pendingPerformanceFee(privateKey, network, address);
      if (BigInt(amount) > 0n) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          const name = await getTokenSymbol(privateKey, network, address);
          return { name, type: 'AutoFarmStrategy', address, tx };
        }
      }
    }
  }

  {
    // PANTHER strategies
    const addresses = [
      // - stkBNB/BUSDv2
      // '0x4046492479a5bA18c2a947A1db75f4f1ef227BF1',
      // - stkBNB/BTCBv2
      // '0xc1d3F1dB60DE17afD7770464BAb05c58129d7Ee0',
      // - stkBNB/ETHv2
      '0x9C009595F330CA8070e78b889183e7b8a96cB962',
      // - stkBNB/CAKEv2
      // '0x1f48dCbCE7fC91180492a7b083472924b4e8a44b',
      // - stkBUSD/USDCv2
      // '0xd802621F65Bd96D76e84E49EecdED49C5acb105d',
      // - stkBNB/USDTv2
      // '0xE0327dA3f94Efe600569Ca68Aa02e6921FD89Bfa',
      // - stkBNB/PANTHERv2
      '0x358582CEeeB0F008495C06206973F5F6e495accd',
      // - stkBUSD/PANTHERv2
      '0x1A51686Fb42861AA7E38c1CF8868877F43F82aA4',
    ];
    for (const address of addresses) {
      const amount = await pendingPerformanceFee(privateKey, network, address);
      if (BigInt(amount) > 0n) {
        const tx = await safeGulp(privateKey, network, address);
        if (tx !== null) {
          const name = await getTokenSymbol(privateKey, network, address);
          return { name, type: 'PantherStrategy', address, tx };
        }
      }
    }
  }

  {
    // CAKE collector
    const address = '0x14bAc5f216337F8da5f41Bb920514Af98ef62c36';
    const amount = await pendingReward(privateKey, network, address);
    if (BigInt(amount) > 20000000000000000000n) { // 20 CAKE
      const tx = await safeGulp(privateKey, network, address);
      if (tx !== null) {
        const name = await getTokenSymbol(privateKey, network, address);
        return { name, type: 'PancakeCollector', address, tx };
      }
    }
  }

  {
    // AUTO/CAKE collector adapter
    const address = '0x626E98ef225A6f79523C9004E8731B793dfd0F68';
    const amount = await pendingSource(privateKey, network, address);
    if (BigInt(amount) > 100000000000000000n) { // 0.1 AUTO
      const tx = await safeGulp(privateKey, network, address);
      if (tx !== null) {
        const name = await getTokenSymbol(privateKey, network, address);
        return { name, type: 'AutoFarmCollectorAdapter', address, tx };
      }
    }
  }

  {
    // CAKE buyback
    const address = '0xC351706C3212D45fc24F6B89e686f07fAb048b16';
    const amount = await pendingBuyback(privateKey, network, address);
    if (BigInt(amount) > 20000000000000000000n) { // 20 CAKE
      const tx = await safeGulp(privateKey, network, address);
      if (tx !== null) {
        const name = await getTokenSymbol(privateKey, network, address);
        return { name, type: 'PancakeBuyback', address, tx };
      }
    }
  }

  {
    // PANTHER buyback adapter
    const address = '0x495089390569d47807F1Db83F14e053002DB25b4';
    const amount = await pendingSource(privateKey, network, address);
    if (BigInt(amount) > 400000000000000000000n) { // 400 PANTHER
      const tx = await safeGulp(privateKey, network, address);
      if (tx !== null) {
        const name = await getTokenSymbol(privateKey, network, address);
        return { name, type: 'PantherBuybackAdapter', address, tx };
      }
    }
  }

  {
    // universal buyback
    const address = '0x139ee66ABc14889921d24dA7e60DdB03dc2E1bEE';
    const [amount1, amount2] = await pendingBurning(privateKey, network, address);
    if (BigInt(amount1) > 0n && BigInt(amount2) > 0n) {
      const tx = await safeGulp(privateKey, network, address);
      if (tx !== null) {
        const name = await getTokenSymbol(privateKey, network, address);
        return { name, type: 'UniversalBuyback', address, tx };
      }
    }
  }

  return false;

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

async function main(args) {
  let [binary, script, network] = args;
  network = network || 'bscmain';

  // handy to list all contracts
  // await listContracts(privateKey, network);
  // return;

  readLastGulp();

  await sendTelegramMessage('<i>GulpBot (' + network + ') Initiated</i>');

  let interrupted = false;
  interrupt(async (e) => {
    if (!interrupted) {
      interrupted = true;
      console.error('error', e, e instanceof Error ? e.stack : undefined);
      const message = e instanceof Error ? e.message : String(e);
      await sendTelegramMessage('<i>GulpBot (' + network + ') Interrupted (' + escapeHTML(message) + ')</i>');
      exit();
    }
  });
  while (true) {
    await sleep(MONITORING_INTERVAL * 1000);
    const lines = [];
    try {
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
    } catch (e) {
      console.error('error', e, e instanceof Error ? e.stack : undefined);
      const message = e instanceof Error ? e.message : String(e);
      lines.push('<i>GulpBot (' + network + ') Failure (' + escapeHTML(message) + ')</i>');
    }
    await sendTelegramMessage(lines.join('\n'));
  }
}

entrypoint(main);
