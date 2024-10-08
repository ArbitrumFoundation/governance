#!/bin/bash
output_dir="./test/signatures"
for CONTRACTNAME in SecurityCouncilManager L1ArbitrumTimelock L2ArbitrumTimelock L2ArbitrumGovernor L2ArbitrumToken L1ArbitrumToken FixedDelegateErc20Wallet UpgradeExecutor SecurityCouncilMemberElectionGovernor SecurityCouncilMemberRemovalGovernor SecurityCouncilNomineeElectionGovernor
do
    echo "Checking for signature changes in $CONTRACTNAME"
    [ -f "$output_dir/$CONTRACTNAME" ] && mv "$output_dir/$CONTRACTNAME" "$output_dir/$CONTRACTNAME-old"
    forge inspect "$CONTRACTNAME" methods > "$output_dir/$CONTRACTNAME"
    diff "$output_dir/$CONTRACTNAME-old" "$output_dir/$CONTRACTNAME"
    if [[ $? != "0" ]]
    then
        CHANGED=1
    fi
done
if [[ $CHANGED == 1 ]]
then
    exit 1
fi