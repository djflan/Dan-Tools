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
   ,@HostSystemId                   INT
)
/*=========================================================
NAME:           [dbo].[LASS_GenerateBillingTransactionDeliveryPointData_LIS_LADS]
DESCRIPTION:    Generates billing delivery point data for LIS and LADS platforms based on
                datastream details.

MODIFICATIONS:
  AUTHOR        date        DESC
  dflanigan     20240310    initial version
=========================================================

=========================================================
*/
AS

BEGIN
    SET NOCOUNT ON

    -- Misc Declarations
    DECLARE @FoundLineItemCalculatorModule BIT = 0
    DECLARE @IsErrorState BIT = 0
    DECLARE @InvoiceWarningMessage NVARCHAR(4000) = ''
    DECLARE @EmptyGuid UNIQUEIDENTIFIER = 0x0
    DECLARE @BillingTransactionTypeGuid UNIQUEIDENTIFIER = @EmptyGuid
    DECLARE @BillingTransactionTypeId INT = -1
    DECLARE @CustomerId INT = -1

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

    -- Billing Transaction Type Guids
    DECLARE @BillingTransactionTypeGuidLetterShop                       UNIQUEIDENTIFIER = '7cd5755a-3827-4d05-ac9e-fe40322947e5'
    DECLARE @BillingTransactionTypeGuidInserts                          UNIQUEIDENTIFIER = '39362017-6b1e-4d75-90a2-75fd0e422756'
    DECLARE @BillingTransactionTypeGuidDuplex                           UNIQUEIDENTIFIER = '3fa59b34-b073-47bb-b196-5541e7367e2a'
    DECLARE @BillingTransactionTypeGuidAdditionalPagesSx                UNIQUEIDENTIFIER = '0a970d9c-fdf0-4a67-ae30-ecdf3c37e1e6'
    DECLARE @BillingTransactionTypeGuidPostage                          UNIQUEIDENTIFIER = '032c0ea6-de40-489e-9889-459e88fff1e8'
    DECLARE @BillingTransactionTypeGuidForeignPostage                   UNIQUEIDENTIFIER = '981259db-bc3e-462a-8819-1a793dca9ca5'
    DECLARE @BillingTransactionTypeGuidProcessed                        UNIQUEIDENTIFIER = '1ef4110f-47d7-4c54-bbed-d037eb6b3ddf'
    DECLARE @BillingTransactionTypeGuidAdditionalPostage                UNIQUEIDENTIFIER = 'f4a7f8fa-966e-4140-ae08-77d03e9434e4'
    DECLARE @BillingTransactionTypeGuidForeignAdditionalPostage         UNIQUEIDENTIFIER = '5e9dcb63-78ae-415a-9100-5a6d0c0f6d77'

    -- Billing Transaction Status Ids
    DECLARE @BillingTransactionStatusIdExcluded                         INT = 3 -- Excluded

    -- Locations
    DECLARE @NashvilleLocationId                                        INT = 4 -- Nashville

    -- Remove Temporary Tables, also removes indexes
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

    -- Determine customer id from invoice generation session key
    SET @CustomerId = (
        SELECT TOP 1 mc.CustomerID FROM dbo.LASS_Invoices i
            INNER JOIN dbo.LASS_ClientConfigurations cc ON i.ClientConfigurationKey = cc.ClientConfigurationKey
            INNER JOIN dbo.tblCustomers mc ON cc.MaestroAccountCode = mc.Account
        WHERE i.InvoiceGenerationSessionKey = @InvoiceGenerationSessionKey)

    -- Match line item calculator module to billing transaction guid
    IF (@LineItemCalculatorModule = @PostageLineItemCalculatorModule)
    BEGIN
        SET @BillingTransactionTypeGuid = @BillingTransactionTypeGuidPostage
    END

    IF (@LineItemCalculatorModule = @InternationalPostageLineItemCalculatorModule)
    BEGIN
        SET @BillingTransactionTypeGuid = @BillingTransactionTypeGuidForeignPostage
    END

    IF (@LineItemCalculatorModule = @InternationalPostageCanadaLineItemCalculatorModule)
    BEGIN
        SET @BillingTransactionTypeGuid = @BillingTransactionTypeGuidForeignPostage
    END

    IF (@LineItemCalculatorModule = @ForceMailSpecialHandlingPostageLineItemCalculatorModule)
    BEGIN
        SET @BillingTransactionTypeGuid = @BillingTransactionTypeGuidProcessed -- no suitable guid for this transaction exists
    END

    IF (@LineItemCalculatorModule = @ForceMailPostageLineItemCalculatorModule)
    BEGIN
        SET @BillingTransactionTypeGuid = @BillingTransactionTypeGuidPostage -- no suitable guid for this transaction exists either
    END

    IF (@LineItemCalculatorModule = @AdditionalPostageLineItemCalculatorModule)
    BEGIN
        SET @BillingTransactionTypeGuid = @BillingTransactionTypeGuidAdditionalPostage
    END

    IF (@LineItemCalculatorModule = @AdditionalPostageInternationalLineItemCalculatorModule)
    BEGIN
        SET @BillingTransactionTypeGuid = @BillingTransactionTypeGuidForeignAdditionalPostage
    END

    IF (@LineItemCalculatorModule = @LetterShopLineItemCalculatorModule)
    BEGIN
        SET @BillingTransactionTypeGuid = @BillingTransactionTypeGuidLetterShop
    END

    IF (@LineItemCalculatorModule = @InsertsLineItemCalculatorModule)
    BEGIN
        SET @BillingTransactionTypeGuid = @BillingTransactionTypeGuidInserts
    END

    IF (@LineItemCalculatorModule = @DuplexLineItemCalculatorModule)
    BEGIN
        SET @BillingTransactionTypeGuid = @BillingTransactionTypeGuidDuplex
    END

    IF (@LineItemCalculatorModule = @AdditionalPagesLineItemCalculatorModule)
    BEGIN
        SET @BillingTransactionTypeGuid = @BillingTransactionTypeGuidAdditionalPagesSx -- we don't classify plexing at this point
    END

    -- Add warning if we cannot identify the customer id
    IF (@CustomerId = -1)
    BEGIN
        SET @IsErrorState = 1
        SET @InvoiceWarningMessage = 'Customer id could not be identified.'

        GOTO AddInvoiceWarningAndStop
    END

    -- Add warning to invoice generation session if host system cannot be identified
    IF (@HostSystemId = 0)
    BEGIN
        SET @IsErrorState = 1
        SET @InvoiceWarningMessage = 'Line item host system could not be identified for delivery point data generation.'

        GOTO AddInvoiceWarningAndStop
    END

    -- Add warning if we cannot identify the billing transaction type guid
    IF (@BillingTransactionTypeGuid = @EmptyGuid)
    BEGIN
        SET @IsErrorState = 1
        SET @InvoiceWarningMessage = 'Cannot match line item calculator module ' + @LineItemCalculatorModule + ' to a billing transaction type guid.'

        GOTO AddInvoiceWarningAndStop
    END
    ELSE
    BEGIN -- Set the billing transaction type id if we identified the billing transaction type guid
        SET @BillingTransactionTypeId = (SELECT TOP 1 btt.BillingTransactionTypeId FROM dbo.tblBillingTransactionTypes btt WHERE btt.BillingTransactionTypeGuid = @BillingTransactionTypeGuid)
    END

    -- Add warning if we cannot identify the billing transaction type id
    IF (@BillingTransactionTypeId = -1)
    BEGIN
        SET @IsErrorState = 1
        SET @InvoiceWarningMessage = 'Cannot find billing transaction type id for billing transaction type guid ' + CAST(@BillingTransactionTypeGuid as NVARCHAR(MAX))

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
        SET @InvoiceWarningMessage = 'No btdpd-generation line item calculator module match found for ' + @LineItemCalculatorModule + ' with host system id ' + @HostSystemId

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
        SET @InvoiceWarningMessage = 'Calculated quantity (' + CAST(@CalculatedQuantity AS VARCHAR) + ') does not match invoiced quantity (' + CAST(@InvoicedQuantity AS VARCHAR) + ')'

        GOTO AddInvoiceWarningAndStop
    END

    -- Create index for table
    IF NOT EXISTS(SELECT name FROM tempdb.sys.indexes WHERE name='IX_QualifiedBillingActivityBatchCategoryDetails_DataStreamDetailId' AND object_id = OBJECT_ID('tempdb..#QualifiedBillingActivityBatchCategoryDetails'))
    BEGIN
        CREATE NONCLUSTERED INDEX IX_QualifiedBillingActivityBatchCategoryDetails_DataStreamDetailId ON #QualifiedBillingActivityBatchCategoryDetails(DataStreamDetailId)
    END

    -- Create billing transaction guid
    DECLARE @BillingTransactionGuid UNIQUEIDENTIFIER = NEWID()

    -- Create a unique user to ensure that the billing transaction id is unique
    DECLARE @UniqueBillingTransactionUserGuid UNIQUEIDENTIFIER = NEWID()
    DECLARE @BillingTransactionUserAdded VARCHAR(MAX) = (SELECT CONCAT('lass-ll-btdp-gen','|',CAST(@InvoiceGenerationSessionKey AS VARCHAR),'|',CAST(@HostSystemId AS VARCHAR),'|',CAST(@UniqueBillingTransactionUserGuid AS VARCHAR(MAX))))

    -- Insert billing transaction (Remote)
    INSERT INTO [LASS].[dbo].[tblBillingTransactionsRemote]
    (   
         [BillingTransactionGuid]
        ,[BillingTransactionTypeId]
        ,[BillingTransactionStatusId]
        ,[CustomerID]
        ,[LocationID]
        ,[CustomerLobID]
        ,[UploadID]
        ,[JobID]
        ,[MaterialID]
        ,[BillingGroup]
        ,[TransactionDate]
        ,[Quantity]
        ,[PageGroup]
        ,[UserAdded]
        ,[DateAdded]
        ,[UserEdited]
        ,[DateEdited]
        ,[IsActive]
        ,[BillingGroupId]
        ,[DataJobID]
    )
    VALUES
    (
         @BillingTransactionGuid
        ,@BillingTransactionTypeId
        ,@BillingTransactionStatusIdExcluded -- Use excluded to prevent further evaluation
        ,@CustomerId
        ,@NashvilleLocationId
        ,null
        ,null
        ,null
        ,null
        ,null
        ,GETDATE()
        ,@InvoicedQuantity -- Set to # invoiced
        ,null
        ,@BillingTransactionUserAdded
        ,GETDATE()
        ,null
        ,null
        ,1
        ,null
        ,null
    )

    -- Get billing transaction id from last insert
    DECLARE @BillingTransactionId INT = (SELECT TOP 1 BillingTransactionId FROM [LASS].[dbo].[tblBillingTransactionsRemote] WHERE UserAdded = @BillingTransactionUserAdded ORDER BY BillingTransactionId DESC)

    -- Create BTDP data (LIS) - Remote
    IF(@HostSystemId = 1)
    BEGIN
        INSERT INTO [LASS].[dbo].[tblBillingTransactionDeliveryPointsRemote]
        (
             [BillingTransactionDeliveryPointGUID]
            ,[BillingTransactionId]
            ,[BillingTransactionGuid]
            ,[City]
            ,[StateRegion]
            ,[PostalCode]
            ,[CountryCode]
            ,[DestinationCode]
            ,[Quantity]
            ,[DateAdded]
            ,[DateEdited]
            ,[UserAdded]
            ,[UserEdited]
            ,[IsActive]
        )
        SELECT
            NEWID(),
            @BillingTransactionId,
            @BillingTransactionGuid,
            UPPER(ldsd.LisCity),
            UPPER(ldsd.LisState),
            ldsd.LisZip,
            null,
            CASE WHEN ldsd.ForeignAddress = 1 THEN 'F' ELSE 'D' END,
            COUNT(ldsd.DataStreamDetailId),
            GETDATE(),
            null,
            @BillingTransactionUserAdded,
            null,
            1
        FROM #QualifiedBillingActivityBatchCategoryDetails qbabcd
            INNER JOIN LetterShop.dbo.LIS_DataStreamDetails ldsd
                ON qbabcd.DataStreamDetailId = ldsd.DataStreamDetailId
        GROUP BY
            ldsd.LisCity,
            ldsd.LisState,
            ldsd.LisZip,
            ldsd.ForeignAddress
    END

    -- Create BTDP data (LADS) - Remote
    IF(@HostSystemId = 2)
    BEGIN
        INSERT INTO [LASS].[dbo].[tblBillingTransactionDeliveryPointsRemote]
        (
             [BillingTransactionDeliveryPointGUID]
            ,[BillingTransactionId]
            ,[BillingTransactionGuid]
            ,[City]
            ,[StateRegion]
            ,[PostalCode]
            ,[CountryCode]
            ,[DestinationCode]
            ,[Quantity]
            ,[DateAdded]
            ,[DateEdited]
            ,[UserAdded]
            ,[UserEdited]
            ,[IsActive]
        )
        SELECT
            NEWID(),
            @BillingTransactionId,
            @BillingTransactionGuid,
            UPPER(ldsd.City),
            UPPER(ldsd.State),
            ldsd.ZipCode,
            null,
            CASE WHEN ldsd.IsForeignMailed = 1 THEN 'F' ELSE 'D' END,
            COUNT(ldsd.DataStreamDetailId),
            GETDATE(),
            null,
            @BillingTransactionUserAdded,
            null,
            1
        FROM #QualifiedBillingActivityBatchCategoryDetails qbabcd
            INNER JOIN LADS.dbo.LADS_DataStreamDetails ldsd
                ON qbabcd.DataStreamDetailId = ldsd.DataStreamDetailId
        GROUP BY
            ldsd.City,
            ldsd.State,
            ldsd.ZipCode,
            ldsd.IsForeignMailed
    END

    -- Insert billing transaction (LASS)
    INSERT INTO [LASS].[dbo].[tblBillingTransactions]
    (
         [BillingTransactionId]
        ,[BillingTransactionGuid]
        ,[BillingTransactionTypeId]
        ,[BillingTransactionStatusId]
        ,[CustomerID]
        ,[LocationID]
        ,[CustomerLobID]
        ,[UploadID]
        ,[JobID]
        ,[MaterialID]
        ,[BillingGroup]
        ,[TransactionDate]
        ,[Quantity]
        ,[PageGroup]
        ,[UserAdded]
        ,[DateAdded]
        ,[UserEdited]
        ,[DateEdited]
        ,[IsActive]
        ,[BillingGroupId]
        ,[DataJobID]
    )
    SELECT
        btr.BillingTransactionId,
        btr.BillingTransactionGuid,
        btr.BillingTransactionTypeId,
        btr.BillingTransactionStatusId,
        btr.CustomerID,
        btr.LocationID,
        btr.CustomerLobID,
        btr.UploadID,
        btr.JobID,
        btr.MaterialID,
        btr.BillingGroup,
        btr.TransactionDate,
        btr.Quantity,
        btr.PageGroup,
        btr.UserAdded,
        btr.DateAdded,
        btr.UserEdited,
        btr.DateEdited,
        btr.IsActive,
        btr.BillingGroupId,
        btr.DataJobID 
    FROM [LASS].[dbo].[tblBillingTransactionsRemote] btr
    WHERE btr.UserAdded = @BillingTransactionUserAdded
    AND btr.BillingTransactionId = @BillingTransactionId

	SET IDENTITY_INSERT [LASS].[dbo].[tblBillingTransactionDeliveryPoints] ON

    -- Insert billing transaction delivery points (LASS)
    INSERT INTO [LASS].[dbo].[tblBillingTransactionDeliveryPoints]
    (
         [BillingTransactionDeliveryPointID]
        ,[BillingTransactionDeliveryPointGUID]
        ,[BillingTransactionId]
        ,[BillingTransactionGuid]
        ,[City]
        ,[StateRegion]
        ,[PostalCode]
        ,[CountryCode]
        ,[DestinationCode]
        ,[Quantity]
        ,[DateAdded]
        --,[DateEdited]
        ,[UserAdded]
        --,[UserEdited]
        ,[IsActive]
    )
    SELECT 
         btdpr.BillingTransactionDeliveryPointID
        ,btdpr.BillingTransactionDeliveryPointGUID
        ,btdpr.BillingTransactionId
        ,btdpr.BillingTransactionGuid
        ,btdpr.City
        ,btdpr.StateRegion
        ,btdpr.PostalCode
        ,btdpr.CountryCode
        ,btdpr.DestinationCode
        ,btdpr.Quantity
        ,btdpr.DateAdded
        --,btdpr.DateEdited
        ,btdpr.UserAdded
        --,btdpr.UserEdited
        ,btdpr.IsActive
    FROM [LASS].[dbo].[tblBillingTransactionDeliveryPointsRemote] btdpr
    WHERE btdpr.UserAdded = @BillingTransactionUserAdded
    AND btdpr.BillingTransactionId = @BillingTransactionId

	SET IDENTITY_INSERT [LASS].[dbo].[tblBillingTransactionDeliveryPoints] OFF

    -- Delete remote btdp data
    DELETE FROM [LASS].[dbo].[tblBillingTransactionDeliveryPointsRemote]
    WHERE UserAdded = @BillingTransactionUserAdded
    AND BillingTransactionId = @BillingTransactionId

    -- Delete remote bt data
    DELETE FROM [LASS].[dbo].[tblBillingTransactionsRemote]
    WHERE UserAdded = @BillingTransactionUserAdded
    AND BillingTransactionId = @BillingTransactionId

    -- Update billing activity batch category details -- add generated billing transaction guid
    UPDATE lbabcd
    SET lbabcd.BillingTransactionGuid = @BillingTransactionGuid
	FROM [LASS].[dbo].[LASS_BillingActivityBatchCategoryDetails] lbabcd
    INNER JOIN #QualifiedBillingActivityBatchCategoryDetails qbabcd 
		ON qbabcd.BillingActivityBatchCategoryDetailKey = lbabcd.BillingActivityBatchCategoryDetailKey

    -- Stop - we are done
	RETURN

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
                ,@BillingTransactionUserAdded
                ,GETDATE()
                ,null
                ,null
                ,1)
            RETURN
        END
    END
END
GO