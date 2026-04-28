# Adjust Total DVP Payload

This payload corrects the initial DVP estimate contained in the DVP quorum activation proposal.

To get the true value of total DVP, run this dune query: https://dune.com/queries/6707930

To get the token contact's value of total DVP, run this command:
```bash
cast call 0x912CE59144191C1204E64559FE8253a0e49E6548 "getTotalDelegation()(uint)" -r $ARB_URL --block <block_number>
```

As of L2 block `457010837`:
```
True value: 5407451149079192893219290111
Contract value: 5458617008862503155958282897
Difference (true - contract): 5407451149079192893219290111 - 5458617008862503155958282897 = -51165859783310262738992786
```

## Dune Query

```sql
WITH latest_balances AS (
  SELECT 
    delegate,
    newBalance,
    evt_block_number
  FROM (
    SELECT 
      delegate,
      newBalance,
      evt_block_number,
      ROW_NUMBER() OVER (PARTITION BY delegate ORDER BY evt_block_time DESC, evt_index DESC) as rn
    FROM arbitrum_arbitrum.l2arbitrumtoken_evt_delegatevoteschanged
  )
  WHERE rn = 1
)
SELECT 
  SUM(newBalance) as total_tokens_delegated,
  COUNT(DISTINCT delegate) as number_of_delegates,
  MAX(evt_block_number) as last_event_block_number
FROM latest_balances
WHERE newBalance > 0
```