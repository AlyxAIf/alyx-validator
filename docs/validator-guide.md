# ALYX Validator Guide

## 1. Install dependencies

```bash
bash install.sh


2. Setup Cosmovisor
bash cosmovisor/setup.sh
3. Initialize node
alyxd init <moniker> --chain-id alyxtest-4
4. Start node
cosmovisor run start
5. Create validator
alyxd tx staking create-validator ...
Save and exit.

### Step 9
Initialize git:
```bash
git init
git branch -M main
