# secrets

One file: the SSH key CI deploys with, encrypted by `ansible-vault`.

```bash
ansible-vault view --vault-password-file <(gh secret list >/dev/null; cat ~/.seans-vault) deploy_key.vault
ansible-vault rekey deploy_key.vault          # when the password changes
```

**This repository is public, so the encrypted blob is world-downloadable.** The
vault password — the `ANSIBLE_VAULT_PASSWORD` secret — is therefore the only
thing between the internet and the account this key opens. Two things follow:

* rotate the key by generating a new one, appending it to the server's
  `authorized_keys`, re-encrypting here, and *removing the old one from the
  server*. Replacing the file alone leaves the old key working;
* the account it opens should not be `root` forever. A `deploy` user in the
  `docker` group can do everything `deploy.yml` asks and nothing else, and then
  a leaked password is a lost deployment rather than a lost machine.

The public half is on the server in `~/.ssh/authorized_keys`, commented
`seans-ci-deploy`.
