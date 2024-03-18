USE LASS
GO

-- Drop Sproc (DEBUG)
IF (OBJECT_ID('tempdb..#LASS_BillingTransactions_NonMaestro_Populate') IS NOT NULL) DROP PROC #LASS_BillingTransactions_NonMaestro_Populate
GO

-- Sproc - create billing transaction data (LIS/LADS)
CREATE PROC #LASS_BillingTransactions_NonMaestro_Populate
    @1InvoiceLineItemKey BIGINT,
    @1LineItemCalculatorModule NVARCHAR(256),
    @1HostSystemId INT
AS
BEGIN
    -- Misc Declarations
    DECLARE @FoundLineItemCalculatorModule BIT = 0

    -- Line Item Calculators
    DECLARE @LetterShopLineItemCalculatorModule                         NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.LetterShop.LetterShopLineItemCalculator'
    DECLARE @PostageLineItemCalculatorModule                            NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.Postage.PostageLineItemCalculator'
    DECLARE @AdditionalPostageLineItemCalculatorModule                  NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.Postage.AdditionalPostageLineItemCalculator'
    DECLARE @AdditionalPagesLineItemCalculatorModule                    NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.LetterShop.AdditionalPagesLineItemCalculator'
    DECLARE @InsertsLineItemCalculatorModule                            NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.LetterShop.InsertsLineItemCalculator'
    DECLARE @DuplexLineItemCalculatorModule                             NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.LetterShop.DuplexLineItemCalculator'
    DECLARE @ForceMailPostageLineItemCalculatorModule                   NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.Postage.ForceMailPostageLineItemCalculator'
    DECLARE @ForceMailSpecialHandlingPostageLineItemCalculatorModule    NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.Postage.ForceMailSpecialHandlingPostageLineItemCalculator'

    -- Qualified Billing Activity Batch Category Details and Amounts
    DECLARE @QualifiedBillingActivityBatchCategoryDetails TABLE (
        [BillingActivityBatchCategoryDetailKey] [bigint] NOT NULL,
        [DataStreamDetailId] [uniqueidentifier] NOT NULL,
        [BillingActivityBatchCategoryQuantity] [bigint] NOT NULL
    )

    -- TODO: Add warning to invoice generation session if host system cannot be identified
    IF (@1HostSystemId = 0)
    BEGIN
        PRINT 'Unknown Host System'
		RETURN
    END
    
	IF (@1HostSystemId = 1) -- Begin Host System Specific Logic (LIS)
	BEGIN
        IF  (@1LineItemCalculatorModule = @LetterShopLineItemCalculatorModule) OR 
            (@1LineItemCalculatorModule = @PostageLineItemCalculatorModule) OR 
            (@1LineItemCalculatorModule = @AdditionalPostageLineItemCalculatorModule) OR
            (@1LineItemCalculatorModule = @AdditionalPagesLineItemCalculatorModule) OR 
            (@1LineItemCalculatorModule = @InsertsLineItemCalculatorModule) OR 
            (@1LineItemCalculatorModule = @DuplexLineItemCalculatorModule)
        BEGIN
            INSERT INTO @QualifiedBillingActivityBatchCategoryDetails (
                [BillingActivityBatchCategoryDetailKey],
                [DataStreamDetailId],
                [BillingActivityBatchCategoryQuantity]
            )
            SELECT
                lbabcd.BillingActivityBatchCategoryDetailKey,
                lbabcd.DataStreamDetailId,
                1
            FROM LASS_InvoiceLineItems (NOLOCK) lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba (NOLOCK)
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd (NOLOCK)
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
            WHERE lili.InvoiceLineItemKey = @1InvoiceLineItemKey

            SET @FoundLineItemCalculatorModule = 1
        END
	END -- END Host System Specific Logic (LIS)

    -- Host System Specific Logic (LADS)
    IF (@1HostSystemId = 2)
    BEGIN

        IF  (@1LineItemCalculatorModule = @LetterShopLineItemCalculatorModule) OR 
            (@1LineItemCalculatorModule = @PostageLineItemCalculatorModule) OR 
            (@1LineItemCalculatorModule = @AdditionalPostageLineItemCalculatorModule) OR
            (@1LineItemCalculatorModule = @InsertsLineItemCalculatorModule) 
        BEGIN
            INSERT INTO @QualifiedBillingActivityBatchCategoryDetails (
                [BillingActivityBatchCategoryDetailKey],
                [DataStreamDetailId],
                [BillingActivityBatchCategoryQuantity]
            )
            SELECT
                lbabcd.BillingActivityBatchCategoryDetailKey,
                lbabcd.DataStreamDetailId,
                1
            FROM LASS_InvoiceLineItems (NOLOCK) lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba (NOLOCK)
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd (NOLOCK)
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
            WHERE lili.InvoiceLineItemKey = @1InvoiceLineItemKey

            SET @FoundLineItemCalculatorModule = 1
        END

        IF  (@1LineItemCalculatorModule = @AdditionalPagesLineItemCalculatorModule)
        BEGIN
            INSERT INTO @QualifiedBillingActivityBatchCategoryDetails (
                [BillingActivityBatchCategoryDetailKey],
                [DataStreamDetailId],
                [BillingActivityBatchCategoryQuantity]
            )
            SELECT
                lbabcd.BillingActivityBatchCategoryDetailKey,
                lbabcd.DataStreamDetailId,
                ldsd.DocumentPaperPageCount - 1
            FROM LASS_InvoiceLineItems (NOLOCK) lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba (NOLOCK)
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd (NOLOCK)
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
                INNER JOIN LADS.dbo.LADS_DataStreamDetails ldsd (NOLOCK)
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @1InvoiceLineItemKey
            AND ldsd.DocumentPageCount > 1

            SET @FoundLineItemCalculatorModule = 1
        END

        IF (@1LineItemCalculatorModule = @DuplexLineItemCalculatorModule)
            BEGIN
            INSERT INTO @QualifiedBillingActivityBatchCategoryDetails (
                [BillingActivityBatchCategoryDetailKey],
                [DataStreamDetailId],
                [BillingActivityBatchCategoryQuantity]
            )
            SELECT
                lbabcd.BillingActivityBatchCategoryDetailKey,
                lbabcd.DataStreamDetailId,
                ldsd.DocumentPageCount - ldsd.DocumentPaperPageCount
            FROM LASS_InvoiceLineItems (NOLOCK) lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba (NOLOCK)
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd (NOLOCK)
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
                INNER JOIN LADS.dbo.LADS_DataStreamDetails ldsd (NOLOCK)
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @1InvoiceLineItemKey
            AND ldsd.DocumentPageCount - ldsd.DocumentPaperPageCount > 0 -- unsure about this

            SET @FoundLineItemCalculatorModule = 1
        END

        IF (@1LineItemCalculatorModule = @ForceMailPostageLineItemCalculatorModule) OR 
           (@1LineItemCalculatorModule = @ForceMailSpecialHandlingPostageLineItemCalculatorModule)
        BEGIN
            INSERT INTO @QualifiedBillingActivityBatchCategoryDetails (
                [BillingActivityBatchCategoryDetailKey],
                [DataStreamDetailId],
                [BillingActivityBatchCategoryQuantity]
            )
            SELECT
                lbabcd.BillingActivityBatchCategoryDetailKey,
                lbabcd.DataStreamDetailId,
                1
            FROM LASS_InvoiceLineItems (NOLOCK) lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba (NOLOCK)
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd (NOLOCK)
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
                INNER JOIN LADS.dbo.LADS_DataStreamDetails ldsd (NOLOCK)
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @1InvoiceLineItemKey
            AND ldsd.IsForceMailed = 1

            SET @FoundLineItemCalculatorModule = 1
        END

    END -- End LADS Host System Specific Logic

    -- If we didn't find a match, return a warning
    IF (@FoundLineItemCalculatorModule = 0)
    BEGIN
        PRINT 'No Match Found for InvoiceLineItemKey: ' + CAST(@1InvoiceLineItemKey AS NVARCHAR(MAX)) + ' HostSystemId: ' + CAST(@1HostSystemId AS NVARCHAR(MAX)) + ' LineItemCalculatorModule: ' + @1LineItemCalculatorModule
        RETURN
    END

    DECLARE @InvoicedQuantity BIGINT = (SELECT TOP 1 lili.Quantity FROM LASS_InvoiceLineItems lili (NOLOCK) where lili.InvoiceLineItemKey = @1InvoiceLineItemKey)
    DECLARE @CalculatedQuantity BIGINT = (SELECT SUM(qbabcd.BillingActivityBatchCategoryQuantity) FROM @QualifiedBillingActivityBatchCategoryDetails qbabcd)
    DECLARE @IsQuantityMatch BIT = (SELECT CASE WHEN @CalculatedQuantity = @InvoicedQuantity THEN 1 ELSE 0 END)
    
    DECLARE @VendorItemName NVARCHAR(MAX) = (
        SELECT TOP 1 vi.VendorItemName
            FROM LASS_InvoiceLineItems lili (NOLOCK) 
        INNER JOIN LASS_VendorItems vi (NOLOCK)
            ON lili.VendorItemKey = vi.VendorItemKey
        WHERE lili.InvoiceLineItemKey = @1InvoiceLineItemKey)

    DECLARE @NumberOfDetails BIGINT = (SELECT COUNT(*) FROM @QualifiedBillingActivityBatchCategoryDetails)
 
    -- Determine if the calculated quantity and invoiced quantity are the same
    SELECT FORMAT(@CalculatedQuantity,'N0') AS CalculatedQuantity, @VendorItemName AS ItemName, FORMAT(@InvoicedQuantity,'N0') AS InvoicedQuantity, @IsQuantityMatch AS IsQuantityMatch, FORMAT(@NumberOfDetails, 'N0') AS QualifiedDataStreamDetailsInBatchCategory
    
    -- TODO: Do not generate billing transaction data when the calculated quantity and invoiced quantity are not the same

END
GO

-- /Sproc

DECLARE @InvoiceGenerationSessionKey INT = 129094 -- 129094 (LADS-AVL) --129247 (LIS-ENT&A)
DECLARE @SalesTaxBatchStatusKeyNew INT = (
    SELECT SalesTaxBatchStatusKey
        FROM LASS.dbo.LASS_SalesTaxBatchStatuses
    WHERE SalesTaxBatchStatusId = '7BB2234C-2EEC-4AC3-BBA0-E4F9EF019E9C')
DECLARE @IsActive BIT = 1

-- Debugging
DECLARE @UseDebugDataForNonServiceInvoiceLineItems BIT = 0
DECLARE @ViewNonServiceInvoiceLineItems BIT = 0
DECLARE @ViewInvoiceLineItemBillingActivityCategoryTypes BIT = 0

-- Non-Service Invoice Line Items
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
	 (3111641, 'Postage', 20, 'FR020100', 'Postage'),
     (3111637, 'Additional Pages', 13, 'P0000000', 'Print'),
     (3111636, 'Lettershop', 31, 'P0000000', 'Print'),
     (3111638, 'Inserts', 2, 'P0000000', 'Print'),
     (3111639, 'Duplex Fee', 9, 'P0000000', 'Print')
END

-- View Non-Service Invoice Line Items (DEBUG)
IF (@ViewNonServiceInvoiceLineItems = 1) 
BEGIN
    SELECT nsili.*, vi.VendorItemName FROM @NonServiceInvoiceLineItems nsili
        INNER JOIN LASS_InvoiceLineItems lili (NOLOCK)
            ON nsili.InvoiceLineItemKey = lili.InvoiceLineItemKey
        INNER JOIN LASS_VendorItems vi (NOLOCK)
            ON lili.VendorItemKey = vi.VendorItemKey
    ORDER BY nsili.InvoiceLineItemKey
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
    
    -- Debug
    IF (@ViewInvoiceLineItemBillingActivityCategoryTypes = 1)
    BEGIN
        SELECT 
            distinct bact.BillingActivityCategoryTypeId, bact.BillingActivityCategoryTypeName, @InvoiceLineItemKey as InvoiceLineItemKey, @LineItemCalculatorModule as LineItemCalculatorModule
        FROM LASS_InvoiceLineItems (NOLOCK) lili
            INNER JOIN LASS_LineItems (NOLOCK) li
                ON lili.LineItemKey = li.LineItemKey
            INNER JOIN LASS_InvoiceLineItemBillingActivities (NOLOCK) liliba 
                ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
            INNER JOIN LASS_BillingActivityBatchCategories (NOLOCK) babc
                ON liliba.BillingActivityBatchCategoryKey = babc.BillingActivityBatchCategoryKey
            INNER JOIN LASS_BillingActivityBatch (NOLOCK) bab
                ON babc.BillingActivityBatchKey = bab.BillingActivityBatchKey
            INNER JOIN LASS_BillingActivityCategoryTypes (NOLOCK) bact
                ON babc.BillingActivityCategoryTypeKey = bact.BillingActivityCategoryTypeKey
        WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey
    END
    -- /Debug

    -- Determine host system
    DECLARE @HostSystemDataStreamDetailId UNIQUEIDENTIFIER = (
    SELECT TOP 1 
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

    -- Attempt to populate the billing transactions table and billing transaction delivery points for the current InvoiceLineItemKey
    EXEC #LASS_BillingTransactions_NonMaestro_Populate @InvoiceLineItemKey, @LineItemCalculatorModule, @HostSystemId

    -- Increment the counter
    SET @CurrentInvoiceLineItemRow = @CurrentInvoiceLineItemRow + 1
END

