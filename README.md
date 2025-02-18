
## Environment Configuration

This project uses three types of configuration files:

1. `.env` - Application runtime configuration
   - Contains non-sensitive application settings
   - Used by the application at runtime

2. `terraform.tfvars` - Infrastructure configuration
   - Contains non-sensitive infrastructure settings
   - Used by Terraform for infrastructure deployment

3. `set-env.sh` - Sensitive configuration
   - Contains AWS credentials and sensitive variables
   - Never committed to version control
   - Copy set-env.sh.template to set-env.sh and fill in your values

Before running any commands:
```bash
source set-env.sh

