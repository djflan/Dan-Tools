USE lass
go

DECLARE @ClientConfigKey INT = 13 --13
DECLARE @InvoiceGenerationSessionKey INT = 136091 --127867
DECLARE @FindClients BIT = 0
DECLARE @LisActiveClients BIT = 0
DECLARE @FindInvoices BIT = 0

IF (@FindInvoices = 0) AND (@FindClients = 0) AND (@InvoiceGenerationSessionKey IS NOT NULL)
BEGIN
    SELECT DISTINCT
           lili.InvoiceLineItemKey,
           lli.LineItemName,
           lli.LineItemDescription,
           lili.Quantity,
           CASE WHEN lli.UseCustomerTaxAddress = 0 THEN 1 ELSE 0 END as UseCustomerTaxAddress,
           lli.IsSalesTaxExportable
    FROM LASS_InvoiceGenerationSessions ligs (NOLOCK)
        -- Join invoices generation session to invoices
        INNER JOIN LASS_Invoices i (NOLOCK)
            ON ligs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
        -- Gets invoice line items
        INNER JOIN LASS_InvoiceLineItems lili (NOLOCK)
            ON lili.InvoiceKey = i.InvoiceKey
        -- Get lass line items
        INNER JOIN LASS_LineItems lli (NOLOCK)
            ON lili.LineItemKey = lli.LineItemKey
               AND lili.InvoiceKey = i.InvoiceKey
        -- Gets client configuration (probably not needed)
        INNER JOIN LASS.dbo.LASS_ClientConfigurations lcc (NOLOCK)
            ON lcc.ClientConfigurationKey = ligs.ClientConfigurationKey
        -- Get invoice line item billing activities
        INNER JOIN LASS_InvoiceLineItemBillingActivities liliba (NOLOCK)
            ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
               AND liliba.IncludeInSalesTaxBatch = 1 -- Include as ST
        -- Get invoice billing activity batch category details
        INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd (NOLOCK)
            ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
    WHERE ligs.InvoiceGenerationSessionKey = @InvoiceGenerationSessionKey
    ORDER BY lili.InvoiceLineItemKey ASC
    RETURN
END

IF (@FindClients = 1)
BEGIN

    IF (@LisActiveClients = 1)
    BEGIN

        DECLARE @EndDate DATETIME = GETDATE()
        DECLARE @StartDate DATETIME = DATEADD(DAY, -30, @EndDate)

        SELECT DISTINCT
               (lcc.ClientConfigurationKey) AS ClientConfigKey,
               lcc.ClientConfigurationName
        FROM LASS_Clients lc (NOLOCK)
            INNER JOIN lass_clientconfigurations lcc (NOLOCK)
                ON lcc.ClientKey = lc.ClientKey
            INNER JOIN LASS_Invoices li (NOLOCK)
                ON li.ClientConfigurationKey = lcc.ClientConfigurationKey
            INNER JOIN LetterShop.dbo.LIS_ClientConfigs lsc (NOLOCK)
                ON lsc.ClientConfigId = lcc.ClientConfigurationId
            INNER JOIN LetterShop.dbo.LIS_FileStreamConfigs lfc (NOLOCK)
                ON lsc.ClientConfigId = lfc.ClientConfigId
            INNER JOIN LetterShop.dbo.LIS_FileStreams lfs (NOLOCK)
                ON lfc.FileStreamConfigId = lfs.FileStreamConfigId
        WHERE lfs.DateAdded BETWEEN @StartDate AND @EndDate AND lfs.IsActive = 1
        ORDER BY lcc.ClientConfigurationName ASC
    RETURN
    END

    SELECT DISTINCT
           (lcc.ClientConfigurationKey) AS ClientConfigKey,
           lcc.ClientConfigurationName
    FROM LASS_Clients lc (NOLOCK)
        INNER JOIN lass_clientconfigurations lcc (NOLOCK)
            ON lcc.ClientKey = lc.ClientKey
        INNER JOIN LASS_Invoices li (NOLOCK)
            ON li.ClientConfigurationKey = lcc.ClientConfigurationKey
    ORDER BY lcc.ClientConfigurationName ASC
    RETURN
END

IF (@FindInvoices = 1)
   AND (@ClientConfigKey IS NOT NULL)
BEGIN
    SELECT li.InvoiceGenerationSessionKey,
           li.ClientConfigurationKey,
           li.InvoiceBillingDate,
           li.DateAdded,
           li.UserAdded,
           li.DateEdited,
           li.IsActive
    FROM LASS_Invoices (NOLOCK) li
    WHERE li.ClientConfigurationKey = @ClientConfigKey
    ORDER BY li.DateAdded DESC
END