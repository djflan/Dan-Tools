USE [LASS]
GO

DROP PROCEDURE [dbo].[LASS_GenerateBillingTransactionDeliveryPointData_LIS_LADS]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[LASS_GenerateBillingTransactionDeliveryPointData_LIS_LADS]
(
    @InvoiceGenerationSessionKey    BIGINT
   ,@InvoiceLineItemKey             BIGINT
   ,@LineItemKey                    BIGINT
   ,@LineItemCalculatorModule       NVARCHAR(256)
   ,@HostSystemId				    INT
)
/*=========================================================
NAME:           [dbo].[LASS_GenerateBillingTransactionDeliveryPointData_LIS_LADS]
DESCRIPTION:    Generates billing delivery point data for LIS and LADS platforms based on
                datstream details.
				  
MODIFICATIONS:
  AUTHOR        date        DESC
  dflanigan     20240310    initial version
=========================================================
--DEBUG
DECLARE @ReturnCode	int
DECLARE @ReturnMsg	nvarchar(256)
DECLARE @InvoiceId UNIQUEIDENTIFIER = ''

EXEC [dbo].[LASS_SalesTaxBatch_Maestro_Populate] @InvoiceId, @UserName, @ReturnCode output, @ReturnMsg output
SELECT @ReturnCode AS ReturnCode, @ReturnMsg AS ReturnMsg
=========================================================
*/
AS

BEGIN
    SET NOCOUNT ON

    -- Misc Declarations
    DECLARE @FoundLineItemCalculatorModule BIT = 0
    DECLARE @IsErrorState BIT = 0
    DECLARE @InvoiceWarningMessage NVARCHAR(4000) = ''

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

    -- Add warning to invoice generation session if host system cannot be identified
    IF (@HostSystemId = 0)
    BEGIN
        SET @IsErrorState = 1
        SET @InvoiceWarningMessage = 'Line item host system could not be identified for delivery point data generation.'
		
        GOTO AddInvoiceWarningAndStop
    END

    IF (@HostSystemId = 1) -- Begin Host System Specific Logic (LIS)
	BEGIN
        IF  (@LineItemCalculatorModule = @LetterShopLineItemCalculatorModule) OR 
            (@LineItemCalculatorModule = @AdditionalPostageLineItemCalculatorModule) OR
            (@LineItemCalculatorModule = @AdditionalPagesLineItemCalculatorModule) OR 
            (@LineItemCalculatorModule = @InsertsLineItemCalculatorModule) OR 
            (@LineItemCalculatorModule = @DuplexLineItemCalculatorModule)
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
            FROM LASS_InvoiceLineItems lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
            WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey

            SET @FoundLineItemCalculatorModule = 1
        END

        IF  (@LineItemCalculatorModule = @PostageLineItemCalculatorModule)
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
            FROM LASS_InvoiceLineItems lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
                INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey
            AND ldsd.IsActive = 1

            SET @FoundLineItemCalculatorModule = 1
        END

        IF  (@LineItemCalculatorModule = @InternationalPostageLineItemCalculatorModule) OR
            (@LineItemCalculatorModule = @AdditionalPostageInternationalLineItemCalculatorModule)
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
            FROM LASS_InvoiceLineItems lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
                INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey
            AND ldsd.ForeignAddress = 1

            SET @FoundLineItemCalculatorModule = 1
        END

        IF  (@LineItemCalculatorModule = @InternationalPostageCanadaLineItemCalculatorModule)
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
            FROM LASS_InvoiceLineItems lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
                INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey
            AND ldsd.ForeignAddress = 1
            AND LisAddressCountry = 'CANADA'

            SET @FoundLineItemCalculatorModule = 1
        END

        IF  (@LineItemCalculatorModule = @ForceMailPostageLineItemCalculatorModule) OR
            (@LineItemCalculatorModule = @ForceMailSpecialHandlingPostageLineItemCalculatorModule)
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
            FROM LASS_InvoiceLineItems lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
                INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey
            AND ldsd.ForceMail = 1

            SET @FoundLineItemCalculatorModule = 1
        END
	END -- END Host System Specific Logic (LIS)

    -- Host System Specific Logic (LADS)
    IF (@HostSystemId = 2)
    BEGIN

        IF  (@LineItemCalculatorModule = @LetterShopLineItemCalculatorModule) OR 
            (@LineItemCalculatorModule = @PostageLineItemCalculatorModule) OR 
            (@LineItemCalculatorModule = @AdditionalPostageLineItemCalculatorModule) OR
            (@LineItemCalculatorModule = @InsertsLineItemCalculatorModule) 
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
            FROM LASS_InvoiceLineItems lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
            WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey

            SET @FoundLineItemCalculatorModule = 1
        END

        IF  (@LineItemCalculatorModule = @AdditionalPagesLineItemCalculatorModule)
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
            FROM LASS_InvoiceLineItems lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
                INNER JOIN LADS.dbo.LADS_DataStreamDetails ldsd
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey
            AND ldsd.DocumentPageCount > 1

            SET @FoundLineItemCalculatorModule = 1
        END

        IF (@LineItemCalculatorModule = @DuplexLineItemCalculatorModule)
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
            FROM LASS_InvoiceLineItems lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
                INNER JOIN LADS.dbo.LADS_DataStreamDetails ldsd
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey
            AND ldsd.DocumentPageCount - ldsd.DocumentPaperPageCount > 0 -- unsure about this

            SET @FoundLineItemCalculatorModule = 1
        END

        IF (@LineItemCalculatorModule = @ForceMailPostageLineItemCalculatorModule) OR 
           (@LineItemCalculatorModule = @ForceMailSpecialHandlingPostageLineItemCalculatorModule)
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
            FROM LASS_InvoiceLineItems lili
                INNER JOIN LASS_InvoiceLineItemBillingActivities liliba
                    ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
                INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd
                    ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
                    AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
                INNER JOIN LADS.dbo.LADS_DataStreamDetails ldsd
                    ON ldsd.DataStreamDetailId = lbabcd.DataStreamDetailId
            WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey
            AND ldsd.IsForceMailed = 1

            SET @FoundLineItemCalculatorModule = 1
        END
    END -- End LADS Host System Specific Logic

    -- Die if no line item calculator module match found
    IF (@FoundLineItemCalculatorModule = 0)
    BEGIN
        SET @IsErrorState = 1
        SET @ErrorMessage = 'No btdp-generation line item calculator module match found for ' + @LineItemCalculatorModule + ' with host system id ' + @HostSystemId

        GOTO AddInvoiceWarningAndStop
    END

    -- Determine if line item invoiced number is equal to the calculated number
    DECLARE @InvoicedQuantity BIGINT = (SELECT TOP 1 lili.Quantity FROM LASS_InvoiceLineItems lili where lili.InvoiceLineItemKey = @InvoiceLineItemKey)
    DECLARE @CalculatedQuantity BIGINT = (SELECT SUM(qbabcd.BillingActivityBatchCategoryQuantity) FROM #QualifiedBillingActivityBatchCategoryDetails qbabcd)
    DECLARE @IsQuantityMatch BIT = (SELECT CASE WHEN @CalculatedQuantity = @InvoicedQuantity THEN 1 ELSE 0 END)

    -- Die if the calculated quantity doesn't match the invoiced quantity
    IF (@IsQuantityMatch = 0)
    BEGIN
        SET @IsErrorState = 1
        SET @ErrorMessage = 'Calculated quantity (' + CAST(@CalculatedQuantity AS VARCHAR) + ') does not match invoiced quantity (' + CAST(@InvoicedQuantity AS VARCHAR) + ')'

        GOTO AddInvoiceWarningAndStop
    END

    -- Create index for table
    IF NOT EXISTS(SELECT name FROM tempdb.sys.indexes WHERE name='IX_QualifiedBillingActivityBatchCategoryDetails_DataStreamDetailId' AND object_id = OBJECT_ID('tempdb..#QualifiedBillingActivityBatchCategoryDetails'))							
	BEGIN
		CREATE NONCLUSTERED INDEX IX_QualifiedBillingActivityBatchCategoryDetails_DataStreamDetailId ON #QualifiedBillingActivityBatchCategoryDetails(DataStreamDetailId)
	END

    -- TODO: INSERT INTO BILLING TRANSACTION TABLE

    -- Create BTDP data (LIS)
    IF(@HostSystemId = 1)
    BEGIN
        SELECT  
            count (ldsd.DataStreamDetailId) as NumDetails,
            ldsd.LisCity,
            ldsd.LisState,
            ldsd.LisZip,
            CASE WHEN ldsd.ForeignAddress = 1 THEN 'Yes' ELSE 'No' END AS ForeignAddress
        FROM #QualifiedBillingActivityBatchCategoryDetails qbabcd
        INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd
            ON qbabcd.DataStreamDetailId = ldsd.DataStreamDetailId
        GROUP BY 
            ldsd.LisCity,
            ldsd.LisState,
            ldsd.LisZip,
            ldsd.ForeignAddress

        -- TODO RETURN
    END


    -- Create BTDP data (LADS)
    IF(@HostSystemId = 2)
    BEGIN
        SELECT  
            count (ldsd.DataStreamDetailId) as NumDetails,
            ldsd.City,
            ldsd.State,
            ldsd.ZipCode
            --ldsd.LisAddressCountry
        FROM #QualifiedBillingActivityBatchCategoryDetails qbabcd
        INNER JOIN LADS.dbo.LADS_DataStreamDetails ldsd
            ON qbabcd.DataStreamDetailId = ldsd.DataStreamDetailId
        GROUP BY 
            ldsd.City,
            ldsd.State,
            ldsd.ZipCode
            --ldsd.LisAddressCountry --TODO: Figure out country for LADS

        -- TODO RETURN
    END

    AddInvoiceWarningAndStop:
    BEGIN
        IF (@IsErrorState = 1)
        BEGIN
            INSERT INTO [LASS].[dbo].[LASS_InvoiceWarnings] (
	    	     [InvoiceWarningId]
	    	    ,[InvoiceGenerationSessionKey]
	    	    ,[LineItemKey]
	    	    ,[InvoiceWarningMessage]
	    	    ,[InvoiceLineItemGroupKey]
	    	    ,[InvoiceLineHeaderKey]
	    	    ,[WarningResolved]
	    	    ,[WarningResolutionDate]
	    	    ,[WarningResolutionDescription]
	    	    ,[UserAdded]
	    	    ,[DateAdded]
	    	    ,[UserEdited]
	    	    ,[DateEdited]
	    	    ,[IsActive])
            VALUES (
	    	     NEWID()
	    	    ,@InvoiceGenerationSessionKey
	    	    ,@LineItemKey
	    	    ,@InvoiceWarningMessage
	    	    ,null
	    	    ,null
	    	    ,0
	    	    ,null
	    	    ,null
	    	    ,'lass-ll-btdp-gen'
	    	    ,GETDATE()
	    	    ,null
	    	    ,null
	    	    ,1)

            RETURN
        END
    END
END