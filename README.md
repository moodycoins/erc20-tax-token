# erc20-tax-token

**Minimal** and **gas optimized** implementations of various ERC20 tax schemes.

## Contracts

```ml
ERC20TaxSwap - "Basic functionality for token that taxes swaps through a UniswapV2 pair"
```

## Testing

Add a `.env` file with a valid RPC endpoint as indicated in `.env.example`:

```txt
MAINNET_RPC_URL = https://mainnet.infura.io/v3/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

```zsh
forge install
forge build
forge test
```

Note: the RPC endpoint must be Mainnet Ethereum (or Goerli), otherwise the V2 router address needs to be updated.

## Safety

This is **experimental software** and is provided on an "as is" and "as available" basis.
