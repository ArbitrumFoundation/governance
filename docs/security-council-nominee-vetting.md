# Nominee vetting guidelines

7 days after an election has begun there is a 14 day vetting period to allow the Foundation to conduct compliance checks on each of the nominees that have received 0.2% of votable tokens. They can then exclude nominees who fail these checks, and include nominees if fewer than 6 nominees have been selected in the Nominee Election phase. The Member Election Governor authorises a specific address that is controlled by the Foundation to do these actions.

### Foundation vetting security best practice

The address authorised to exclude and include addresses should be a multisig that allows for address rotation for the following reasons:

- Inclusion and exclusion is a powerful role that could be used to manipulate elections. An m-of-n multisig will help to guard against key compromise
- To change the vetting address in the member election governor requires a Constitutional proposal, or Security Council emergency action, so the Foundation should use a multisig to manage their own key rotation rather than being able to rotate the authorised address.

### Excluding addresses

7 days after an election has begun there is a 14 day vetting period to allow the Foundation to conduct compliance checks on each of the nominees that have received 0.2% of votable tokens. Amongst other things the Foundation should consider:

- Does the entity behind the address conform to all legal requirements that the Foundation has of Security Council members?
- Is the entity a member of an organisation that if all nominees were elected would result in having more than 3 members of that organisation in the Security Council? As an example, if there are already 2 members of an org in the other cohort then only 1 member can be selected as a nominee for the current election.
- Is the address already a member of the opposite cohort? The contracts check that this was not the case at the time of creation, but manipulation in the Manager could cause this to be violated at a later time.
- Is the owner of the address able to create a signature of all chains where a Security Council is located that will be accepted by a Gnosis Safe?

If any of the above are false the Foundation should call `excludeNominee` to stop that address from proceeding to the next stage.

### Including addresses

During the 14 day vetting period the Foundation should include new addresses if the number of nominees that achieved a threshold of 0.2% of votable tokens and have not been excluded is less than 6. They should include new addresses until there are a total of 6 nominees that will progress to the next stage. New addresses should be selected in the following order, if each stage does not yield enough included addresses to make up to 6 nominees then the Foundation should progress to the next stage:

1. Members from the outgoing cohort that fulfil the requirements to not be excluded should be chosen at random.
2. Contenders who did not receive 0.2% threshold of votes should be included, in order of votes descending
3. If there still aren’t 6 nominees the Foundation may include any address they see fit

In the event that the Foundation does not fill these spots the DAO or Security Council will need to take action to remedy the situation.
