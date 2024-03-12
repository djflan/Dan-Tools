USE LASS
GO

DECLARE @InvoiceGenerationSessionKey INT = 129247
DECLARE @SalesTaxBatchStatusKeyNew INT =
        (
            SELECT SalesTaxBatchStatusKey
            FROM LASS.dbo.LASS_SalesTaxBatchStatuses
            WHERE SalesTaxBatchStatusId = '7BB2234C-2EEC-4AC3-BBA0-E4F9EF019E9C'
        )
DECLARE @IsActive BIT = 1

-- Temp Tables
-- Sales Tax Batches
DECLARE @LassSalesTaxBatches TABLE
(
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
    [IsActive] [bit] NOT NULL
)

-- Sales Tax Batch Details
/*
DECLARE @LassSalesTaxBatchDetails TABLE
(
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
*/

IF (0 = 1)
BEGIN
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
    SELECT NEWID(),
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
    WHERE ligs.InvoiceGenerationSessionKey = @InvoiceGenerationSessionKey
    GROUP BY lili.InvoiceLineItemKey,
             lili.InvoiceLineItemGroupKey,
             lili.LineItemKey,
             lstc.TaxCode,
             lli.SalesTaxItemCategory
END
ELSE
BEGIN
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
    VALUES
    (NEWID(), 3111640, 1, 'NCOA', 17, 'SD020900', 'Service', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111641, 1, 'Postage', 20, 'FR020100', 'Postage', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111637, 1, 'Additional Pages', 13, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111643, 1, 'ReturnLogic', 29, 'SD020900', 'Service', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111636, 1, 'Lettershop', 31, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111638, 1, 'Inserts', 2, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111639, 1, 'Duplex Fee', 9, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111642, 1, 'ReturnLogic', 32, 'SD020900', 'Service', 'dflanigan', GETDATE(), 1)
END

SELECT COUNT(distinct lbabcd.BillingActivityBatchCategoryDetailId), lstb.InvoiceLineItemKey, lstb.InvoiceLineItemGroupKey, lstb.LineItemKey, lili.InvoiceLineItemKey
FROM @LassSalesTaxBatches lstb
    INNER JOIN LASS_InvoiceLineItems lili (NOLOCK)
        ON lili.InvoiceLineItemKey = lstb.InvoiceLineItemKey
    INNER JOIN LASS_ClientLineItems lcli (NOLOCK)
        ON lili.LineItemKey = lcli.LineItemKey
    INNER JOIN LASS_InvoiceLineItemBillingActivities liliba (NOLOCK)
        ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
    INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd (NOLOCK)
        ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
        AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey

GROUP BY lstb.InvoiceLineItemKey, lstb.InvoiceLineItemGroupKey, lstb.LineItemKey, lili.InvoiceLineItemKey
ORDER by lili.InvoiceLineItemKey

