I'll research Digital Ocean's droplet cloning and storage backup capabilities to help you test safely without risking your production system.Perfect! I found the key information about Digital Ocean cloning and backup strategies. Here's what you can do:

## ✅ **YES - You Can Clone Your Droplet AND Attached Storage**

### Method 1: Complete Cloning (Recommended for Testing)

**Step 1: Snapshot the Volume (Block Storage)**
```bash
# Via DO Control Panel:
# Go to Volumes → Click "More" next to your volume → "Take snapshot"
# Name it something like "onlyoffice-storage-test-backup"
```

**Step 2: Snapshot the Droplet**
```bash
# Via DO Control Panel:
# Go to Droplets → Click your droplet → Click "Snapshots" → "Take Snapshot"
# Name it something like "onlyoffice-droplet-test-backup"
```

**Step 3: Create New Droplet from Snapshots**
```bash
# Create new droplet from droplet snapshot
# Create new volume from volume snapshot
# Attach the new volume to the new droplet
```

### Method 2: Use Digital Ocean's API/CLI (Automated)

You can orchestrate snapshot actions using Doctl. Here are some helpful commands when working with snapshots:

```bash
# Install doctl if not already installed
sudo snap install doctl

# Authenticate with your DO API token
doctl auth init

# Create volume snapshot
doctl compute volume snapshot <volume-id> --snapshot-name "test-volume-backup"

# Create droplet snapshot  
doctl compute droplet snapshot <droplet-id> --snapshot-name "test-droplet-backup"

# Create new volume from snapshot
doctl compute volume create test-volume --snapshot <snapshot-id> --region nyc3

# Create new droplet from snapshot
doctl compute droplet create test-droplet --image <snapshot-id> --size s-2vcpu-4gb --region nyc3
```

## Key Findings from Research:

**✅ Volume Snapshots Work Independently**: Creating a snapshot of a Droplet does not capture block storage volumes attached to the Droplet. Block storage volumes are network-based block devices that provide additional data storage for Droplets. You can move them between Droplets and resize them at any time. You can create snapshots of block storage volumes separately.

**✅ Volumes Can Be Moved**: You can use the Volumes page in the Control Panel to find your volume. Hover over the name of the droplet it's connected to and click "Edit". You can now choose a new droplet to mount the volume to.

**✅ Cost Effective**: DigitalOcean Snapshots are charged at $0.06/Gb per month. Pricing is based on the size of the final snapshot and not the size of the droplet disk capacity or filesystem being saved.

## **Your Safe Testing Strategy:**

1. **Snapshot both** your droplet and volume (about $5-10 for storage)
2. **Create test environment** from snapshots  
3. **Test the reboot fix** on the clone
4. **Once proven**, apply to production
5. **Delete test environment** when done

**This gives you a complete copy to safely test reboots without risking your 8th installation!**