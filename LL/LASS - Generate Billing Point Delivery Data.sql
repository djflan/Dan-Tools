USE LASS
GO

DECLARE @InvoiceGenerationSessionKey INT = 129094 --129247
DECLARE @SalesTaxBatchStatusKeyNew INT = (
    SELECT SalesTaxBatchStatusKey
        FROM LASS.dbo.LASS_SalesTaxBatchStatuses
    WHERE SalesTaxBatchStatusId = '7BB2234C-2EEC-4AC3-BBA0-E4F9EF019E9C')
DECLARE @IsActive BIT = 1

DECLARE @CreateNewBatches BIT = 1
DECLARE @BatchCreationDebug BIT = 0

-- temp
DECLARE @BillingActivityBatches TABLE (
    [LineItemCalculatorModule] [nvarchar](256) NOT NULL,
    [BillingActivityBatchId] [uniqueidentifier] NOT NULL,
    [BillingActivityBatchMetaGroupKey] [bigint] NOT NULL,
    [IsMaestroBatch] [bit] NOT NULL
)
-- /temp


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

IF (@CreateNewBatches = 1)
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

    -- Debug
    IF (@BatchCreationDebug = 1) 
    BEGIN
        SELECT * FROM @LassSalesTaxBatches
        ORDER BY InvoiceLineItemKey
        RETURN
    END
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
    -- (NEWID(), 3111640, 1, 'NCOA', 17, 'SD020900', 'Service', 'dflanigan', GETDATE(), 1),
    -- (NEWID(), 3111641, 1, 'Postage', 20, 'FR020100', 'Postage', 'dflanigan', GETDATE(), 1),
    -- (NEWID(), 3111637, 1, 'Additional Pages', 13, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111643, 1, 'ReturnLogic', 29, 'SD020900', 'Service', 'dflanigan', GETDATE(), 1),
    -- (NEWID(), 3111636, 1, 'Lettershop', 31, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    -- (NEWID(), 3111638, 1, 'Inserts', 2, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    -- (NEWID(), 3111639, 1, 'Duplex Fee', 9, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111642, 1, 'ReturnLogic', 32, 'SD020900', 'Service', 'dflanigan', GETDATE(), 1)
END

DECLARE @TotalInvoiceLineItemRows INT = ( SELECT COUNT(*) FROM @LassSalesTaxBatches )

DECLARE @CurrentInvoiceLineItemRow INT = 1

WHILE @CurrentInvoiceLineItemRow <= @TotalInvoiceLineItemRows
BEGIN
    -- Get the InvoiceLineItemKey for the current row
    DECLARE @InvoiceLineItemKey BIGINT = (
        SELECT InvoiceLineItemKey
    FROM (
        SELECT InvoiceLineItemKey, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS RowNum
        FROM @LassSalesTaxBatches) AS T
    WHERE RowNum = @CurrentInvoiceLineItemRow)

    -- Get the LineItemCalculatorModule for the current InvoiceLineItemKey
    DECLARE @LineItemCalculatorModule NVARCHAR(128) = (
        SELECT li.LineItemCalculatorModule
            FROM LASS_InvoiceLineItems (NOLOCK) lili
        INNER JOIN LASS_LineItems (NOLOCK) li
            ON lili.LineItemKey = li.LineItemKey
    WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey)
    
    INSERT INTO @BillingActivityBatches
    (
        LineItemCalculatorModule,
        BillingActivityBatchId,
        BillingActivityBatchMetaGroupKey,
        IsMaestroBatch
    )
    SELECT 
        @LineItemCalculatorModule, 
        bab.BillingActivityBatchId, 
        @CurrentInvoiceLineItemRow, 
        bab.IsMaestroBatch 
    FROM LASS_InvoiceLineItems (NOLOCK) lili
        INNER JOIN LASS_LineItems (NOLOCK) li
            ON lili.LineItemKey = li.LineItemKey
        INNER JOIN LASS_InvoiceLineItemBillingActivities (NOLOCK) liliba 
            ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
        INNER JOIN LASS_BillingActivityBatchCategories (NOLOCK) babc
            ON liliba.BillingActivityBatchCategoryKey = babc.BillingActivityBatchCategoryKey
        INNER JOIN LASS_BillingActivityBatch (NOLOCK) bab
            ON babc.BillingActivityBatchKey = bab.BillingActivityBatchKey
    WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey
    -- /bab

    --SELECT @LineItemCalculatorModule

    -- Increment the counter
    SET @CurrentInvoiceLineItemRow = @CurrentInvoiceLineItemRow + 1
END

select * from @BillingActivityBatches



