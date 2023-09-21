# erc20-tax-token

**Minimal** and **gas optimized** implementation of an ERC20 token with taxable swaps.

## ERC20TaxSwap

```ml
ERC20TaxSwap - "Basic functionality for token that taxes swaps through a UniswapV2 pair"
```

### Features

- Taxes are taken on swaps to any router contracts
- Taxes are accumulated in the contract until the contract balance `> swapThreshold`, at which point a swap to `$ETH` will be triggered during the next transfer or sale
- Taxes are divided into three (optional) components
  - `teamFee`
  - `protocolFee` (e.g. revenue shares)
  - `liquidityFee` (distributed back into the LP)
- The max the contract can swap at once is determined by the `maxContractSwap` variable

### Deployment

A test contract is deployed on Goerli to:

```sol
address testDeploymentAddress = 0x8CD907A8502258CD7bb959B0BDEe179255B132F3;
```

The fee breakdown is:

```sol
uint8 teamFee = 1;
uint8 protocolFee = 1;
uint8 liquidityFee = 1;
```

You can try interacting with it on [Uniswap](https://app.uniswap.org/swap?outputCurrency=0x8CD907A8502258CD7bb959B0BDEe179255B132F3&chain=goerli). Make sure to set slippage greater than 3%.

### Configuration

A blacklist and transaction limits can be enabled in the constructor with `limitsActive` and `blacklistActive` arguments. Furthermore, various configuration parameters have been set to reasonable values, but can be updated (**warning**: misconfiguring these variables can cause problems):

```sol
// The balance at which the contract attempts to swap to ETH
swapThreshold = initialSupply.mulDiv(5, 10000); // 0.05%

// The max that can be swapped at once
maxContractSwap = initialSupply.mulDiv(50, 10000); // 0.5%

// If limits are active, the max size of a buy or sell
maxTransaction = initialSupply.mulDiv(100, 10000); // 1%

// If limits are active, the max wallet size
maxWallet = initialSupply.mulDiv(100, 10000); // 1%
```

#### Minting

By default, the `initialSupply` is minted in the constructor and the token is no longer mintable. To change this, you would need write a new function utilizing the ERC20 `_mint(address to, uint amount)` function.

**Note**: It's recommended to keep `initialSupply` as a hard cap and base the mint schedule around this hard cap. This way parameters like `swapThreshold` can be based around the `initialSupply`, whereas a tax token with a completely unpredictable supply would be hard to configure.

## Testing

Add a `.env` file with a valid RPC endpoint as indicated in `.env.example`:

```txt
MAINNET_RPC_URL = https://mainnet.infura.io/v3/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Then run:

```zsh
forge install
npm install
npm run build
npm run test
```

**Note**: the RPC endpoint must be Mainnet Ethereum (or Goerli), otherwise the V2 router address needs to be updated.

## Safety

This is **experimental software** and is provided on an "as is" and "as available" basis.
