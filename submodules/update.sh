# Step 1: merge in latest updates from main/master
git submodule update --init --remote --merge

# Step 2: add any changed submodules
git add submodules/

# Step 3: commit changes
git commit -m "Update submodules" -e
