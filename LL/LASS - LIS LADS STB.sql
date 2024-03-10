USE LASS
GO

DECLARE @InvoiceGenerationSessionKey INT = 129247
DECLARE @SalesTaxBatchStatusKeyNew INT = (SELECT SalesTaxBatchStatusKey
FROM LASS.dbo.LASS_SalesTaxBatchStatuses
WHERE SalesTaxBatchStatusId = '7BB2234C-2EEC-4AC3-BBA0-E4F9EF019E9C')
DECLARE @IsActive BIT = 1

-- Temp Tables
-- Sales Tax Batches
DECLARE @LassSalesTaxBatches TABLE (
    --  [SalesTaxBatchKey] [bigint] NOT NULL,
    [SalesTaxBatchId] [uniqueidentifier] NOT NULL,
    [InvoiceLineItemKey] [bigint] NULL,
    [SalesTaxBatchStatusKey] [bigint] NOT NULL,
    [InvoiceLineItemGroupKey] [nvarchar](128) NULL,
    [LineItemKey] [bigint] NULL,
    [TaxCode] [nvarchar](15) NULL,
    [TaxCategory] [nvarchar](15) NULL,
    [UserAdded] [nvarchar](128) NOT NULL,
    [DateAdded] [datetime] NOT NULL,
    [IsActive] [bit] NOT NULL)

-- Sales Tax Batch Details
DECLARE @LassSalesTaxBatchDetails TABLE (
		 [SalesTaxBatchDetailId]
		,[SalesTaxBatchKey]
		,[Quantity]
		,[Rate]
		,[City]
		,[Region]
		,[Zip]
		,[IsForeign]
		,[ShouldExport]
		,[UserAdded]
		,[DateAdded]
		,[IsActive]
        )

-- Create New Batches
INSERT INTO @LassSalesTaxBatches
    (
    SalesTaxBatchId,
    InvoiceLineItemKey,
    SalesTaxBatchStatusKey,
    InvoiceLineItemGroupKey,
    LineItemKey,
    TaxCode,
    TaxCategory,
    UserAdded,
    DateAdded,
    IsActive
    )
SELECT
    NEWID(),
    lili.InvoiceLineItemKey,
    @SalesTaxBatchStatusKeyNew,
    lili.InvoiceLineItemGroupKey,
    lili.LineItemKey,
    lstc.TaxCode,
    lli.SalesTaxItemCategory,
    'dflanigan',
    GETDATE(),
    @IsActive
FROM LASS_InvoiceGenerationSessions ligs (NOLOCK)
    -- Join invoices generation session to invoices
    INNER JOIN LASS_Invoices i (NOLOCK)
    ON ligs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
    -- Gets invoice line items
    INNER JOIN LASS_InvoiceLineItems lili (NOLOCK)
    ON lili.InvoiceKey = i.InvoiceKey
    -- Get lass line items
    INNER JOIN LASS_LineItems lli (NOLOCK)
    ON lli.LineItemKey = lili.LineItemKey
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
    -- Join Sales Tax Codes
    INNER JOIN LASS_SalesTaxCodes (NOLOCK) lstc
    ON lstc.SalesTaxCodeKey = lli.SalesTaxCodeKey
WHERE 
    ligs.InvoiceGenerationSessionKey = @InvoiceGenerationSessionKey
GROUP BY 
    lili.InvoiceLineItemKey,
    lili.InvoiceLineItemGroupKey,
    lili.LineItemKey,
    lstc.TaxCode,
    lli.SalesTaxItemCategory

SELECT *
FROM @LassSalesTaxBatches