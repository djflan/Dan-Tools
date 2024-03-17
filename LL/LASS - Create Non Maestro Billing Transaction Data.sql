USE LASS
GO

IF (OBJECT_ID('tempdb..#LASS_BillingTransactions_NonMaestro_Populate') IS NOT NULL)
    DROP PROC #LASS_BillingTransactions_NonMaestro_Populate
GO

-- Sproc - create billing transaction data (LIS/LADS)
CREATE PROC #LASS_BillingTransactions_NonMaestro_Populate
    @1InvoiceLineItemKey BIGINT,
    @1LineItemCalculatorModule NVARCHAR(256),
    @1HostSystemId INT
AS
BEGIN
    -- TODO: Add warning to invoice generation session if host system cannot be identified
    IF (@1HostSystemId = 0)
    BEGIN
        PRINT 'Unknown Host System'
		RETURN
    END
    ELSE
    BEGIN
		PRINT CAST(@1InvoiceLineItemKey AS NVARCHAR(MAX)) + ' ' + CAST(@1HostSystemId AS NVARCHAR(MAX)) + ' ' + @1LineItemCalculatorModule
		
		IF (@1HostSystemId = 1) -- LIS
		BEGIN
			SELECT top 1 * from tblBillingTransactions
			SELECT * FROM tblBillingTransactionTypes
		END

    END
END
GO

-- /Sproc

DECLARE @InvoiceGenerationSessionKey INT = 129247 -- 129094 (LADS-AVL) --129247 (LIS-ENT&A)
DECLARE @SalesTaxBatchStatusKeyNew INT = (
    SELECT SalesTaxBatchStatusKey
        FROM LASS.dbo.LASS_SalesTaxBatchStatuses
    WHERE SalesTaxBatchStatusId = '7BB2234C-2EEC-4AC3-BBA0-E4F9EF019E9C')
DECLARE @IsActive BIT = 1

DECLARE @UseDebugDataForNonServiceInvoiceLineItems BIT = 1
DECLARE @ViewNonServiceInvoiceLineItems BIT = 0

-- temp
-- DECLARE @BillingActivityBatches TABLE (
--     [LineItemCalculatorModule] [nvarchar](256) NOT NULL,
--     [BillingActivityBatchId] [uniqueidentifier] NOT NULL,
--     [BillingActivityBatchMetaGroupKey] [bigint] NOT NULL,
--     [IsMaestroBatch] [bit] NOT NULL
-- )
-- /temp

-- Sales Tax Batches
DECLARE @NonServiceInvoiceLineItems TABLE
(
    [InvoiceLineItemKey] [bigint] NULL,
    [InvoiceLineItemGroupKey] [nvarchar](128) NULL,
    [LineItemKey] [bigint] NULL,
    [TaxCode] [nvarchar](15) NULL,
    [TaxCategory] [nvarchar](15) NULL
)

IF (@UseDebugDataForNonServiceInvoiceLineItems = 0)
BEGIN
    -- Create New Batches
    INSERT INTO @NonServiceInvoiceLineItems
    (
        InvoiceLineItemKey,
        InvoiceLineItemGroupKey,
        LineItemKey,
        TaxCode,
        TaxCategory
    )
    SELECT 
           lili.InvoiceLineItemKey,
           lili.InvoiceLineItemGroupKey,
           lili.LineItemKey,
           lstc.TaxCode,
           lli.SalesTaxItemCategory
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
       -- INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd (NOLOCK)
       --     ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
        -- Join Sales Tax Codes
        INNER JOIN LASS_SalesTaxCodes (NOLOCK) lstc
            ON lstc.SalesTaxCodeKey = lli.SalesTaxCodeKey
    WHERE ligs.InvoiceGenerationSessionKey = @InvoiceGenerationSessionKey                   -- Filter by session
	AND lli.UseCustomerTaxAddress = 0                                                       -- Exclude service lines (Generated later)
    AND NOT (EXISTS(                                                                        -- Exclude lines with dpd data                                
            SELECT * FROM LASS_BillingActivityBatchCategoryDetails (NOLOCK) lbabcd2
                INNER JOIN tblBillingTransactionDeliveryPoints (NOLOCK) btdp
                    ON btdp.BillingTransactionGuid = lbabcd2.BillingTransactionGuid AND btdp.IsActive = 1
            WHERE lbabcd2.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey)
        )
    GROUP BY lili.InvoiceLineItemKey,
             lili.InvoiceLineItemGroupKey,
             lili.LineItemKey,
             lstc.TaxCode,
             lli.SalesTaxItemCategory
END
ELSE
BEGIN
    INSERT INTO @NonServiceInvoiceLineItems
    (
        InvoiceLineItemKey,
        InvoiceLineItemGroupKey,
        LineItemKey,
        TaxCode,
        TaxCategory
    )
    VALUES
	 (3111641, 'Postage', 20, 'FR020100', 'Postage')--,
    --  (3111637, 'Additional Pages', 13, 'P0000000', 'Print'),
    --  (3111636, 'Lettershop', 31, 'P0000000', 'Print'),
    --  (3111638, 'Inserts', 2, 'P0000000', 'Print'),
    --  (3111639, 'Duplex Fee', 9, 'P0000000', 'Print')
END

IF (@ViewNonServiceInvoiceLineItems = 1) 
BEGIN
    SELECT * FROM @NonServiceInvoiceLineItems
    ORDER BY InvoiceLineItemKey
    --RETURN
END

DECLARE @TotalInvoiceLineItemRows INT = ( SELECT COUNT(*) FROM @NonServiceInvoiceLineItems )

DECLARE @CurrentInvoiceLineItemRow INT = 1

WHILE @CurrentInvoiceLineItemRow <= @TotalInvoiceLineItemRows
BEGIN
    -- Get the InvoiceLineItemKey for the current row
    DECLARE @InvoiceLineItemKey BIGINT = (
        SELECT InvoiceLineItemKey
    FROM (
        SELECT InvoiceLineItemKey, ROW_NUMBER() OVER (ORDER BY (InvoiceLineItemKey)) AS RowNum
        FROM @NonServiceInvoiceLineItems) AS T
    WHERE RowNum = @CurrentInvoiceLineItemRow)

    -- Get the LineItemCalculatorModule for the current InvoiceLineItemKey
    DECLARE @LineItemCalculatorModule NVARCHAR(128) = (
        SELECT li.LineItemCalculatorModule
            FROM LASS_InvoiceLineItems (NOLOCK) lili
        INNER JOIN LASS_LineItems (NOLOCK) li
            ON lili.LineItemKey = li.LineItemKey
    WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey)
    
    /*
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
    */
    -- /bab

    -- *Determine host system

    DECLARE @HostSystemDataStreamDetailId UNIQUEIDENTIFIER = (
    SELECT top 1 
        lbabcd.DataStreamDetailId -- all billing activity batch category details are from a single source system
    FROM LASS_InvoiceLineItemBillingActivities (NOLOCK) liliba
        INNER JOIN LASS_BillingActivityBatchCategories (NOLOCK) lbabc
            ON liliba.BillingActivityBatchCategoryKey = lbabc.BillingActivityBatchCategoryKey
        INNER JOIN LASS_BillingActivityBatchCategoryDetails (NOLOCK) lbabcd
            ON lbabc.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
    WHERE liliba.InvoiceLineItemKey = @InvoiceLineItemKey)

    DECLARE @HostSystemId INT = 0;  -- Unknown / NotSet

    IF @HostSystemId = 0 AND EXISTS ( SELECT * FROM LetterShop.dbo.LIS_DataStreamDetails (NOLOCK) WHERE DataStreamDetailId = @HostSystemDataStreamDetailId)
    BEGIN
        SET @HostSystemId = 1       -- LIS
    END

    IF @HostSystemId = 0 AND EXISTS ( SELECT * FROM LADS.dbo.LADS_DataStreamDetails (NOLOCK) WHERE DataStreamDetailId = @HostSystemDataStreamDetailId)
    BEGIN
        SET @HostSystemId = 2       -- LADS
    END

    -- /Determine host system

    -- Attempt to populate the billing transactions for the current InvoiceLineItemKey
    EXEC #LASS_BillingTransactions_NonMaestro_Populate @InvoiceLineItemKey, @LineItemCalculatorModule, @HostSystemId
    

    -- Increment the counter
    SET @CurrentInvoiceLineItemRow = @CurrentInvoiceLineItemRow + 1
END

-- select count(distinct lbab.UserAdded) as BabAdds, count(b.BillingActivityBatchId) as NumBatches, b.LineItemCalculatorModule, b.BillingActivityBatchMetaGroupKey from @BillingActivityBatches  b
--     inner join LASS_BillingActivityBatch lbab (NOLOCK) on lbab.BillingActivityBatchId = b.BillingActivityBatchId
--     group by b.BillingActivityBatchMetaGroupKey, b.LineItemCalculatorModule
--where b.BillingActivityBatchMetaGroupKey = 7



