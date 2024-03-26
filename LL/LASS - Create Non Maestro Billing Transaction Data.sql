USE LASS
GO

-- Drop Sproc (DEBUG)
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
    -- Debug
    DECLARE @ShowInvoiceLineItemQualificationSummaryForAll BIT = 0
    DECLARE @ShowInvoiceLineItemQualificationSummaryForNonMatched BIT = 0
    DECLARE @ShowNonMatchedDetailMetadata BIT = 0

    -- Misc Declarations
    DECLARE @FoundLineItemCalculatorModule BIT = 0

    -- Line Item Calculators
    DECLARE @AdditionalPagesLineItemCalculatorModule                    NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.LetterShop.AdditionalPagesLineItemCalculator'
    DECLARE @DuplexLineItemCalculatorModule                             NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.LetterShop.DuplexLineItemCalculator'
    DECLARE @InsertsLineItemCalculatorModule                            NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.LetterShop.InsertsLineItemCalculator'
    DECLARE @LetterShopLineItemCalculatorModule                         NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.LetterShop.LetterShopLineItemCalculator'

    DECLARE @AdditionalPostageInternationalLineItemCalculatorModule     NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.Postage.AdditionalPostageInternationalLineItemCalculator'
    DECLARE @AdditionalPostageLineItemCalculatorModule                  NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.Postage.AdditionalPostageLineItemCalculator'
    DECLARE @ForceMailPostageLineItemCalculatorModule                   NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.Postage.ForceMailPostageLineItemCalculator'
    DECLARE @ForceMailSpecialHandlingPostageLineItemCalculatorModule    NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.Postage.ForceMailSpecialHandlingPostageLineItemCalculator'
    DECLARE @InternationalPostageCanadaLineItemCalculatorModule         NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.Postage.InternationalPostageCanadaLineItemCalculator'
    DECLARE @InternationalPostageLineItemCalculatorModule               NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.Postage.InternationalPostageLineItemCalculator'
    DECLARE @PostageLineItemCalculatorModule                            NVARCHAR(256) = 'LL.Components.LASS.LineItemCalculators.Postage.PostageLineItemCalculator'

    -- Remove Temporary Tables
    IF OBJECT_ID('tempdb..#QualifiedBillingActivityBatchCategoryDetails') IS NOT NULL
    BEGIN
    	DROP TABLE #QualifiedBillingActivityBatchCategoryDetails
    END

    -- Qualified Billing Activity Batch Category Details and Amounts
    CREATE TABLE #QualifiedBillingActivityBatchCategoryDetails (
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
            (@1LineItemCalculatorModule = @AdditionalPostageLineItemCalculatorModule) OR
            (@1LineItemCalculatorModule = @AdditionalPagesLineItemCalculatorModule) OR 
            (@1LineItemCalculatorModule = @InsertsLineItemCalculatorModule) OR 
            (@1LineItemCalculatorModule = @DuplexLineItemCalculatorModule)
        BEGIN
            INSERT INTO #QualifiedBillingActivityBatchCategoryDetails (
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

        IF  (@1LineItemCalculatorModule = @PostageLineItemCalculatorModule)
        BEGIN
            INSERT INTO #QualifiedBillingActivityBatchCategoryDetails (
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
                INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd (NOLOCK)
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @1InvoiceLineItemKey
            AND ldsd.IsActive = 1

            SET @FoundLineItemCalculatorModule = 1
        END

        IF  (@1LineItemCalculatorModule = @InternationalPostageLineItemCalculatorModule) OR
            (@1LineItemCalculatorModule = @AdditionalPostageInternationalLineItemCalculatorModule)
        BEGIN
            INSERT INTO #QualifiedBillingActivityBatchCategoryDetails (
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
                INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd (NOLOCK)
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @1InvoiceLineItemKey
            AND ldsd.ForeignAddress = 1

            SET @FoundLineItemCalculatorModule = 1
        END

        IF  (@1LineItemCalculatorModule = @InternationalPostageCanadaLineItemCalculatorModule)
        BEGIN
            INSERT INTO #QualifiedBillingActivityBatchCategoryDetails (
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
                INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd (NOLOCK)
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @1InvoiceLineItemKey
            AND ldsd.ForeignAddress = 1
            AND LisAddressCountry = 'CANADA'

            SET @FoundLineItemCalculatorModule = 1
        END

        IF  (@1LineItemCalculatorModule = @ForceMailPostageLineItemCalculatorModule) OR
            (@1LineItemCalculatorModule = @ForceMailSpecialHandlingPostageLineItemCalculatorModule)
        BEGIN
            INSERT INTO #QualifiedBillingActivityBatchCategoryDetails (
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
                INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd (NOLOCK)
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @1InvoiceLineItemKey
            AND ldsd.ForceMail = 1

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
            INSERT INTO #QualifiedBillingActivityBatchCategoryDetails (
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
            INSERT INTO #QualifiedBillingActivityBatchCategoryDetails (
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
            INSERT INTO #QualifiedBillingActivityBatchCategoryDetails (
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
            INSERT INTO #QualifiedBillingActivityBatchCategoryDetails (
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
        SELECT 'No Calculator Module Match Found' as Warning, 
        @1InvoiceLineItemKey as InvoiceLineItemKey,
        CASE WHEN @1HostSystemId = 1 THEN 'LIS' WHEN @1HostSystemId = 2 THEN 'LADS' ELSE 'UNKNOWN' END as Host,
        @1LineItemCalculatorModule as LineItemCalculatorModule
        RETURN
    END

    DECLARE @InvoicedQuantity BIGINT = (SELECT TOP 1 lili.Quantity FROM LASS_InvoiceLineItems lili (NOLOCK) where lili.InvoiceLineItemKey = @1InvoiceLineItemKey)
    DECLARE @CalculatedQuantity BIGINT = (SELECT SUM(qbabcd.BillingActivityBatchCategoryQuantity) FROM #QualifiedBillingActivityBatchCategoryDetails qbabcd)
    DECLARE @IsQuantityMatch BIT = (SELECT CASE WHEN @CalculatedQuantity = @InvoicedQuantity THEN 1 ELSE 0 END)
    
    IF  (@ShowInvoiceLineItemQualificationSummaryForAll = 1) OR 
        (@ShowInvoiceLineItemQualificationSummaryForNonMatched = 1)
    BEGIN
        -- Get the VendorItemName for the InvoiceLineItem
        DECLARE @VendorItemName NVARCHAR(MAX) = (
            SELECT TOP 1 vi.VendorItemName
                FROM LASS_InvoiceLineItems lili (NOLOCK) 
            INNER JOIN LASS_VendorItems vi (NOLOCK)
                ON lili.VendorItemKey = vi.VendorItemKey
            WHERE lili.InvoiceLineItemKey = @1InvoiceLineItemKey)

        -- Get the number of details for the InvoiceLineItem
        DECLARE @NumberOfDetails BIGINT = (SELECT COUNT(*) FROM #QualifiedBillingActivityBatchCategoryDetails)
    
        -- Determine if the calculated quantity and invoiced quantity are the same
        IF  (@ShowInvoiceLineItemQualificationSummaryForAll = 1) OR 
            (@ShowInvoiceLineItemQualificationSummaryForNonMatched = 1 AND @IsQuantityMatch = 0)
        BEGIN
            SELECT 
                CASE 
                    WHEN @1HostSystemId = 1 THEN 'LIS'
                    WHEN @1HostSystemId = 2 THEN 'LADS' 
                    ELSE 'Unknown' 
                END as Host, 
                    @1InvoiceLineItemKey as InvoiceLineItemKey,
                    FORMAT(@CalculatedQuantity,'N0') AS '#Calc', 
                    FORMAT(@InvoicedQuantity,'N0') AS '#Inv', 
                    @IsQuantityMatch AS Valid, 
                    @VendorItemName AS Item, 
                    FORMAT(@NumberOfDetails, 'N0') AS '#CatDetails', 
                    @1LineItemCalculatorModule as Module
        END
    END

    -- TODO: Do not generate billing transaction data when the calculated quantity and invoiced quantity are not the same
    GOTO ENDING
    IF (@IsQuantityMatch = 1) -- Generate billing transaction data
    BEGIN
         -- DEBUG FOR NOW
        -- Create index for table
        IF NOT EXISTS(SELECT name FROM tempdb.sys.indexes WHERE name='IX_QualifiedBillingActivityBatchCategoryDetails_DataStreamDetailId' AND object_id = OBJECT_ID('tempdb..#QualifiedBillingActivityBatchCategoryDetails'))							
	    BEGIN
	    	CREATE NONCLUSTERED INDEX IX_QualifiedBillingActivityBatchCategoryDetails_DataStreamDetailId ON #QualifiedBillingActivityBatchCategoryDetails(DataStreamDetailId)
	    END

        IF(@1HostSystemId = 1)
        BEGIN
            SELECT  
                count (ldsd.DataStreamDetailId) as NumDetails,
                ldsd.LisCity,
                ldsd.LisState,
                ldsd.LisZip,
                CASE WHEN ldsd.ForeignAddress = 1 THEN 'Yes' ELSE 'No' END AS ForeignAddress
            FROM #QualifiedBillingActivityBatchCategoryDetails qbabcd (NOLOCK)
            INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd (NOLOCK)
                ON qbabcd.DataStreamDetailId = ldsd.DataStreamDetailId
            GROUP BY 
                ldsd.LisCity,
                ldsd.LisState,
                ldsd.LisZip,
                ldsd.ForeignAddress
        END

        IF(@1HostSystemId = 2)
        BEGIN
            SELECT  
                count (ldsd.DataStreamDetailId) as NumDetails,
                ldsd.City,
                ldsd.State,
                ldsd.ZipCode
                --ldsd.LisAddressCountry
            FROM #QualifiedBillingActivityBatchCategoryDetails qbabcd (NOLOCK)
            INNER JOIN LADS.dbo.LADS_DataStreamDetails ldsd (NOLOCK)
                ON qbabcd.DataStreamDetailId = ldsd.DataStreamDetailId
            GROUP BY 
                ldsd.City,
                ldsd.State,
                ldsd.ZipCode
                --ldsd.LisAddressCountry --TODO: Figure out country for LADS
        END
    END  -- End Generate billing transaction data
    ELSE -- Quantity does not match
    BEGIN
        IF (@ShowNonMatchedDetailMetadata = 1)
        BEGIN
            -- Non-Matched Details (LIS)
            IF (@1HostSystemId = 1)
            BEGIN
                SELECT qbabcd.* FROM #QualifiedBillingActivityBatchCategoryDetails qbabcd (NOLOCK)
                    INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd (NOLOCK)
                        ON qbabcd.DataStreamDetailId = ldsd.DataStreamDetailId
            END
            -- Non-Matched Details (LADS)
            IF (@1HostSystemId = 2)
            BEGIN
                SELECT ldsd.* FROM #QualifiedBillingActivityBatchCategoryDetails qbabcd (NOLOCK)
                    INNER JOIN LADS.dbo.LADS_DataStreamDetails ldsd (NOLOCK)
                        ON qbabcd.DataStreamDetailId = ldsd.DataStreamDetailId
            END
        END
    END
    ENDING:
    -- DBG
    PRINT 
    CONCAT(
        @1InvoiceLineItemKey,
        ' - Matched: ', 
        CAST(@IsQuantityMatch AS INT),
        ' - Calc: ',
        @CalculatedQuantity,
        ' - Inv: ',
        @InvoicedQuantity,
        ' - Module: ',
        @1LineItemCalculatorModule)

END
GO

-- /Sproc

DECLARE @InvoiceGenerationSessionKey INT = 129247--131466 -- 129094 (LADS-AVL) --129247 (LIS-ENT&A)
DECLARE @SalesTaxBatchStatusKeyNew INT = (SELECT SalesTaxBatchStatusKey FROM LASS.dbo.LASS_SalesTaxBatchStatuses WHERE SalesTaxBatchStatusId = '7BB2234C-2EEC-4AC3-BBA0-E4F9EF019E9C')

-- Debugging
DECLARE @UseDebugDataForNonServiceInvoiceLineItems BIT = 0
DECLARE @ViewNonServiceInvoiceLineItems BIT = 0
DECLARE @ViewInvoiceLineItemBillingActivityCategoryTypes BIT = 0

-- Remove Temporary Tables
IF OBJECT_ID('tempdb..#NonServiceInvoiceLineItems') IS NOT NULL
BEGIN
	DROP TABLE #NonServiceInvoiceLineItems
END

-- Non-Service Invoice Line Items
CREATE TABLE #NonServiceInvoiceLineItems 
(
    [InvoiceLineItemKey] [bigint] NULL,
    [InvoiceLineItemGroupKey] [nvarchar](128) NULL,
    [LineItemKey] [bigint] NULL,
    [TaxCode] [nvarchar](15) NULL,
    [TaxCategory] [nvarchar](15) NULL
)

IF (@UseDebugDataForNonServiceInvoiceLineItems = 0)
BEGIN
    INSERT INTO #NonServiceInvoiceLineItems
    (
        InvoiceLineItemKey,
        InvoiceLineItemGroupKey,
        LineItemKey,
        TaxCode,
        TaxCategory
    )
    SELECT 
    --top 1 -- (DEBUG)
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
    INSERT INTO #NonServiceInvoiceLineItems
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
    SELECT nsili.*, vi.VendorItemName FROM #NonServiceInvoiceLineItems nsili
        INNER JOIN LASS_InvoiceLineItems lili (NOLOCK)
            ON nsili.InvoiceLineItemKey = lili.InvoiceLineItemKey
        INNER JOIN LASS_VendorItems vi (NOLOCK)
            ON lili.VendorItemKey = vi.VendorItemKey
    ORDER BY nsili.InvoiceLineItemKey
END

DECLARE @TotalInvoiceLineItemRows INT = ( SELECT COUNT(*) FROM #NonServiceInvoiceLineItems )
DECLARE @CurrentInvoiceLineItemRow INT = 1

WHILE @CurrentInvoiceLineItemRow <= @TotalInvoiceLineItemRows
BEGIN
    -- Get the InvoiceLineItemKey for the current row
    DECLARE @InvoiceLineItemKey BIGINT = (
        SELECT InvoiceLineItemKey
    FROM (
        SELECT InvoiceLineItemKey, ROW_NUMBER() OVER (ORDER BY (InvoiceLineItemKey)) AS RowNum
        FROM #NonServiceInvoiceLineItems) AS T
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

    DECLARE @Test NVARCHAR(MAX) =
    (SELECT vi.VendorItemName FROM LASS_InvoiceLineItems lili (NOLOCK) 
        INNER JOIN LASS_LineItems li (NOLOCK)
            ON lili.LineItemKey = li.LineItemKey
        INNER JOIN LASS_VendorItems vi (NOLOCK)
            ON li.VendorItemKey = vi.VendorItemKey
    WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey)

    PRINT @Test

    IF (@Test like '%International%') OR (1=1) -- debug
    BEGIN
    -- Attempt to populate the billing transactions table and billing transaction delivery points for the current InvoiceLineItemKey
    EXEC #LASS_BillingTransactions_NonMaestro_Populate @InvoiceLineItemKey, @LineItemCalculatorModule, @HostSystemId
    END

    -- Increment the counter
    SET @CurrentInvoiceLineItemRow = @CurrentInvoiceLineItemRow + 1
END

