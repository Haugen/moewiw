# Deploying Azure Monitor + Application Insights

## What Was Added

### Infrastructure (Terraform)

1. **Log Analytics Workspace** - Central data store for logs/metrics
2. **Application Insights** - APM for tracking page performance
3. **Diagnostic Settings** - Enabled on VM, NSG, ACR, and Key Vault
4. **Key Vault Secret** - App Insights connection string stored securely

### Application

1. **JavaScript SDK** - Added to `index.html` for client-side tracking
2. **CI/CD Integration** - GitHub Actions injects connection string during build

## Deployment Steps

### 1. Apply Terraform Changes

```bash
cd infra
terraform plan
terraform apply
```

This will create:

- `moewiw-law` (Log Analytics Workspace)
- `moewiw-appinsights` (Application Insights)
- Diagnostic settings for all resources
- App Insights connection string in Key Vault

**Note**: The first `terraform apply` might take 2-3 minutes as Azure provisions the monitoring resources.

### 2. Verify Resources Created

Check that these resources exist in the Azure Portal:

- Log Analytics Workspace: `moewiw-law`
- Application Insights: `moewiw-appinsights`
- Key Vault secret: `appinsights-connection-string`

### 3. Deploy Application

Push your changes to trigger the GitHub Actions workflow:

```bash
git add .
git commit -m "Add Azure Monitor and Application Insights"
git push origin main
```

The CI/CD pipeline will:

1. Fetch the App Insights connection string from Key Vault
2. Inject it into `index.html` (replacing the placeholder)
3. Build the Docker image with the instrumented HTML
4. Deploy to your VM

### 4. Verify Monitoring is Working

#### Option A: Visit Your Website

Simply visit your website's public IP. Within 30 seconds, you should see data in Application Insights.

#### Option B: Check Application Insights

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to Resource Group: `moewiw`
3. Open: `moewiw-appinsights`
4. Click on "Live Metrics" (you'll see real-time data as you browse)

#### Option C: View a Page View in Logs

1. In Application Insights, click "Logs"
2. Run this query:
   ```kusto
   pageViews
   | where timestamp > ago(1h)
   | project timestamp, name, url, duration, client_Browser
   ```

### 5. Explore the Dashboards

Navigate through these sections in Application Insights:

- **Application Dashboard** - Overview metrics
- **Live Metrics** - Real-time monitoring
- **Performance** - Response time analysis
- **Failures** - Error tracking
- **Users** - Geographic distribution
- **Usage** - User behavior analytics

## What You'll See

### Immediate Data (within 30 seconds)

- Page views
- Performance metrics (load time)
- Browser/OS information
- Geographic location

### Within 5 minutes

- VM metrics (CPU, memory, disk)
- ACR login events (from image pulls)
- Key Vault access logs

### After a few hours

- NSG flow logs (connection details)
- Aggregated performance trends
- User session analytics

## Cost

With normal usage (a few visitors per day):

- **Data Ingestion**: ~10-50 MB/month
- **Cost**: $0/month (stays well within 5GB free tier)

## Troubleshooting

### App Insights not showing data?

1. **Check if connection string was injected**:

   ```bash
   # SSH into VM
   ssh azureuser@<vm-ip>

   # Check the running container
   docker exec webapp cat /usr/share/nginx/html/index.html | grep "InstrumentationKey"
   ```

   Should show the actual connection string, not "APPINSIGHTS_CONNECTION_STRING_PLACEHOLDER"

2. **Check browser console**:
   Open your website, press F12, and check the Console tab. You should see Application Insights loading.

3. **Verify Key Vault secret exists**:
   ```bash
   az keyvault secret show --vault-name moewiw-kv --name appinsights-connection-string --query value -o tsv
   ```

### Diagnostic logs not appearing?

Diagnostic settings can take 5-15 minutes to start flowing data after being enabled. Be patient!

## KQL Query Examples

### Most Common Queries

```kusto
// All page views today
pageViews
| where timestamp > startofday(now())

// Slowest page loads
pageViews
| where duration > 1000  // slower than 1 second
| project timestamp, url, duration, client_Browser

// Visitors by country
pageViews
| summarize Visitors = dcount(user_Id) by client_CountryOrRegion
| order by Visitors desc

// Browser breakdown
pageViews
| summarize count() by client_Browser
| render piechart

// Performance over time
pageViews
| summarize avg(duration) by bin(timestamp, 1h)
| render timechart

// Key Vault access audit
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where OperationName == "SecretGet"
| project TimeGenerated, CallerIPAddress, Resource, resultSignature

// ACR image pulls
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.CONTAINERREGISTRY"
| where OperationName == "Pull"
| project TimeGenerated, repository_s, tag_s
```

## Next Steps

Now that monitoring is in place, you can:

1. Set up alerts for downtime or slow performance
2. Create custom dashboards and workbooks
3. Add custom events (track button clicks, form submissions, etc.)
4. Configure availability tests from multiple global locations
5. Explore metrics from all your infrastructure resources

Enjoy watching your static HTML file with enterprise-grade monitoring! 🎉
