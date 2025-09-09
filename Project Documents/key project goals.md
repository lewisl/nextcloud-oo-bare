# Nextcloud + OnlyOffice Development Plan

## Goals
- Host: Hetzner Germany (privacy)
- No Docker/Snap preferred
- Native LAMP + NextCloud and OnlyOffice installation
- Remote key server via VPN for encryption--implement after NextCloud + OnlyOffice are functional in test and production

## Domains
- Test: test-collab-site.com        COMPLETED
- Production: bedfordfallsbbbl.org  COMPLETED

## Next Steps
1. Create Hetzner test VPS:  COMPLETED
2. Set up Cloudron for analysis
3. SSH agent development approach
4. Create bare install scripts
5. Production migration

## Working Directories
- Current: nextcloud-onlyoffice/
- Valid goals and background: Project Documents/


## Current Status
- Fixing native LAMP installation
- Test domain: test-collab-site.com
- Production: bedfordfallsbbbl.org
- SSH agent development on Hetzner test VPS

## Key Decisions
1. Analyze manual deployment (working reference)
2. localhost mapping to application servers
3. Remote key server integration via VPN (postpone until reliable automated deployment is working)
4. Update-resistant PHP encryption hooks (or have simple "installation" in place for required modifications of default deployment)

## REVISED DECISIONS
2. copy the working production version to test (test-collab-site.com). initially, make no changes until new strategy agreed upon
      - my guess is this will be MUCH harder than it seems because we will copy from one url to another
      - the test domain does not have the required subdomains for the Cloudron deployment
      - the test domain does not have the required subdomains for 3rd party mail forwarding
      - there may be many cases in which the not-so-good open source code contains hardcoded url paths rather than using environment variables for url paths.  Unfortunately, "fixing" this code will not be resilient as it will be over-written by updates
3. Analyze working reference, currently deployed with Cloudron on production at bedfordfallsbbbl.org:
      - Cloudron relies on 3 domains or subdomains
      - Cloudron enables use of external document editing server and treats OnlyOffice as if it's external though it is physically on same server (vps)
4. Possible changes with no containers script driven deployment
   1. Don't use multiple subdomains and ip addresses
   2. Use localhost access to NextCloud and OnlyOffice behind a single nginx instance
      - Better internet research revealed that single server deployment with localhost access to application servers is common and reliable
      - Previous attempts had ignored or misunderstood required php and NextCloud configs to enable this
      - See document ```Project Documents/chatgpt research.md```

## Next Session Tasks
1. Set up Hetzner test VPS                      COMPLETED
2. Create Cloudflare test domain                COMPLETED
3. create working reference implementation      COMPLETED
4. Provide SSH access for agent development
5. Start with Cloudron teardown analysis

## Technical Requirements
- Server-side encryption with remote key storage
- Survive Nextcloud/OnlyOffice updates
- Native installation (no Docker/containers)