# SSH Keys

Place your public key files here. Example:

```bash
# Generate a new key pair
ssh-keygen -t rsa -b 4096 -f ./ssh-keys/aws-key

# This creates:
# - aws-key (private key - keep secure)
# - aws-key.pub (public key - used by Terraform)
```

The Terraform configuration will automatically create AWS Key Pairs from the .pub files in this directory.
