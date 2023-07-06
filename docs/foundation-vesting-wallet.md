# Arbitrum Foundation Administrative Budget Wallet

The Arbitrum Foundation Administrative Budget Wallet implements the contract specified in [AIP-1.1](https://forum.arbitrum.foundation/t/proposal-aip-1-1-lockup-budget-transparency/13360). The wallet escrows funds which are unlocked over a linear four year schedule; once unlocked, funds can be claimed by a multisig wallet controlled by the Arbitrum Foundation. 

Escrowed $ARB cannot be used to vote on governance proposals. Additionally, the Budget Wallet delegates its votes to the "exclude address" (see ["Vote Exclusion"](./overview.md)); thus, its escrowed $ARB isn't counted towards the governance quorum denominator. 

As per AIP-1.1, the DAO has the ability to change the Budget Wallet's unlock schedule. This can be done via a governance proposal which migrates the wallet's funds to a new wallet which enforces a new schedule (see [here](../test/ArbitrumFoundationVestingWallet.t.sol) for test code). Note that the DAO is also the proxy-owner of the Budget Wallet and thus could vote to upgrade its implementation logic arbitrarily; however, for adjusting its unlock schedule, the migration method is the preferable recommendation. 

