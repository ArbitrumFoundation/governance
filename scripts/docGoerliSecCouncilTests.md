# Goerli Security Council tests

1. Deploy goerli gov
2. Deploy the a test note store by setting the following env vars and running `yarn deploy:note-store`:
    ```
    export DEPLOY_RPC=<goerli rpc>
    export DEPLOY_KEY=<test key with some goerli funds>

    yarn run deploy:note-store
    ```
3. Take the output and execute it via gnosis
4. Manually verify by checking ether/arbiscan that the note was correctly set