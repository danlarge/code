# GitHub Setup Summary (Lowercase `code` Repo)

You’re using **~/Applications_Uncontained/GitHubRepos/code/** (all lowercase).  
Everything is already correct. Just ensure every command or path uses lowercase `code`.

---

## 1. Run your multi-repo updater
```bash
~/Applications_Uncontained/GitHubRepos/code/github_allreposupdate.sh
```

---

## 2. Run your save script (to store any new script in the repo)
```bash
~/Applications_Uncontained/GitHubRepos/code/save_to_code.sh -s /path/to/script.sh -G
```
To put it in a subfolder inside the repo:
```bash
~/Applications_Uncontained/GitHubRepos/code/save_to_code.sh -s /path/to/script.sh -p scripts -G
```
To rename it while saving:
```bash
~/Applications_Uncontained/GitHubRepos/code/save_to_code.sh -s /path/to/script.sh -n newname.sh -G
```

---

## 3. Verify Git identity (already correct)
```bash
git config --global user.name
git config --global user.email
```
Expected output:
```
Dan Large
gitpublic@danlarge.net
```

---

## 4. Confirm commits show correct name
```bash
cd ~/Applications_Uncontained/GitHubRepos/code
git log --format='%h %an <%ae> | %cn <%ce>' -n 3
```
Expected output:
```
Dan Large <gitpublic@danlarge.net> | Dan Large <gitpublic@danlarge.net>
```

---

✅ **Repo path:** `~/Applications_Uncontained/GitHubRepos/code/`  
✅ **Save helper path:** same folder  
✅ **Identity:** fixed  
✅ **History:** rewritten and pushed  

You can now use the save script anytime to back up new scripts to your GitHub repo with one line.


### 1a. Updater behavior (amended)
- Automatically discovers the correct branch without a prior fetch:
  - Uses `git ls-remote --symref origin HEAD` to read the remote’s default branch.
  - Falls back only to branches that actually exist on the remote (`main`, then `master`).
- Clearer skip messages:
  - `origin has no branch '<branch>'` when the guessed branch doesn’t exist remotely.
  - `fetch error for origin/<branch> (...)` with a short diagnostic if the fetch fails.
- Repos without an `origin` remote are still skipped as before.