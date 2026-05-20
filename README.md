# SUU-App-O

### How to run:

1. Start AWS Session, paste access keys and session token into .aws/credentials
   
2. Deploy using init.sh script

### Accessing MCP by LLM CLI (tested on Gemini CLI):

1. Install Gemini CLI:
   ```
   npm install -g @google/gemini-cli
   ```
2. Run Gemini CLI - will require login into google account

3. Exit CLI and add MCP to CLI:
   ```
   gemini mcp add --transport sse grafana-lab http://<EC2-instance-ip>:30090/sse
   ```
4. Enter CLI and verify if it was added using ```/mcp```