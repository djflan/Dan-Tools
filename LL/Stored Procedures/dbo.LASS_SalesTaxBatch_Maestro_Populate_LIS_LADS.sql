USE [LASS]
GO

DROP PROCEDURE [dbo].[LASS_SalesTaxBatch_Maestro_Populate_LIS_LADS]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[LASS_SalesTaxBatch_Maestro_Populate_LIS_LADS]
(
     @InvoiceGenerationSessionId        UNIQUEIDENTIFIER = NULL
    ,@UserName                          NVARCHAR(128)
    ,@ReturnCode                        INT             OUTPUT
    ,@ReturnMsg                         NVARCHAR(256)   OUTPUT
)
/*=========================================================
NAME:             [dbo].[LASS_SalesTaxBatch_Maestro_Populate]
DESCRIPTION:      Creates Sales Tax Batches for maestro for the print transactions

MODIFICATIONS:
  AUTHOR        date        DESC
  mgolden       20190312    Initial Version - APX-3702 - Delivery Point Grouping and NCOA categorization for Sales Tax
  mgolden       20190329    APX-3096 - Connect to Avalara to request sales tax data, then hibernate
  mgolden       20190528    APX-3095 - Basic Billing Bundles (Added iliba.IncludeInSalesTaxBatch = 1)
=========================================================
--DEBUG
DECLARE @UserName   NVARCHAR(128) = 'mgolden'
DECLARE @ReturnCode int
DECLARE @ReturnMsg  nvarchar(256)
DECLARE @InvoiceGenerationSessionId UNIQUEIDENTIFIER = 'BB42BEE9-2499-4BBF-958B-BAA87CD90FF9'

EXEC [dbo].[LASS_SalesTaxBatch_Maestro_Populate]  @InvoiceGenerationSessionId, @UserName, @ReturnCode output, @ReturnMsg output
SELECT @ReturnCode AS ReturnCode, @ReturnMsg AS ReturnMsg
=========================================================
*/

AS

BEGIN

    SET NOCOUNT ON

    BEGIN  -- Variable Declarations


        -- Set default return
        SET @ReturnCode = 0
        SET @ReturnMsg = 'Process not completed.'

        -- Create Profiler Trace Variables
        -- Event Numbers 82-91 are for the 'User Configurable (0-9)' events.
        DECLARE @TraceStartEventId  INT = 84
        DECLARE @TraceEndEventId    INT = 85
        DECLARE @TraceUserInfo      NVARCHAR(128)

        DECLARE @ErrorMessage       NVARCHAR(4000)
        DECLARE @ErrorSeverity      INT
        DECLARE @ErrorState         INT

        DECLARE @CurrentDate                                        DATETIME        = GETDATE()
        DECLARE @IsActive                                           BIT             = 1

        DECLARE @BillingActivityCategoryStatusKeyNew                INT = (SELECT BillingActivityCategoryStatusKey FROM LASS.dbo.LASS_BillingActivityCategoryStatuses WHERE BillingActivityCategoryStatusId = '52DFDB53-C888-476B-BB2D-B76AD23768EB')
        DECLARE @SalesTaxBatchStatusKeyNew                          INT = (SELECT SalesTaxBatchStatusKey FROM LASS.dbo.LASS_SalesTaxBatchStatuses WHERE SalesTaxBatchStatusId = '7BB2234C-2EEC-4AC3-BBA0-E4F9EF019E9C')

    END

    BEGIN TRY

        BEGIN TRAN LASS_SalesTaxBatch_Populate

        -- Create a sales tax batch and sales tax batch detail records for each transaction that has tblBillingTransactionDeliveryPoints records.
        -- Service type records will not have any tblBillingTransactionDeliveryPoints records, so they won't have any entries.
        -- LASS will create a single LASS_SalesTaxBatch and LASS_SalesTaxBatchDetail record for service line items at the time of invoice creation.
        INSERT INTO LASS.dbo.LASS_SalesTaxBatch
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
            ili.InvoiceLineItemKey,
            @SalesTaxBatchStatusKeyNew,
            ili.InvoiceLineItemGroupKey,
            ili.LineItemKey,
            stc.TaxCode,
            li.SalesTaxItemCategory,
            @UserName,
            GETDATE(),
            @IsActive
        FROM LASS.dbo.LASS_invoices i
            INNER JOIN LASS.dbo.LASS_InvoiceGenerationSessions igs ON igs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
            INNER JOIN LASS.dbo.LASS_InvoiceLineItems ili ON ili.InvoiceKey = i.InvoiceKey
            INNER JOIN LASS.dbo.LASS_LineItems li ON li.LineItemKey = ili.LineItemKey
            INNER JOIN LASS.dbo.LASS_SalesTaxCodes stc ON stc.SalesTaxCodeKey = li.SalesTaxCodeKey
            INNER JOIN LASS.dbo.LASS_InvoiceLineItemBillingActivities iliba ON iliba.InvoiceLineItemKey = ili.InvoiceLineItemKey AND iliba.IncludeInSalesTaxBatch = 1
        -- Only create a batch for line items that have delivery point records.
        WHERE igs.InvoiceGenerationSessionId = @InvoiceGenerationSessionId
            AND (EXISTS(SELECT *
                        FROM LASS.dbo.LASS_BillingActivityBatchCategoryDetails babcd
                             INNER JOIN LASS.dbo.tblBillingTransactionDeliveryPoints btdp ON btdp.BillingTransactionGuid = babcd.BillingTransactionGuid AND btdp.IsActive = 1
                        WHERE babcd.BillingActivityBatchCategoryKey = iliba.BillingActivityBatchCategoryKey)
                 -- Create a batch if the line item should use the customer tax address
                 -- There won't be any delivery points associated to the category details with this setting (Services)
                 OR li.UseCustomerTaxAddress = 1)
        GROUP BY ili.InvoiceLineItemKey,
                 ili.InvoiceLineItemGroupKey,
                 ili.LineItemKey,
                 stc.TaxCode,
                 li.SalesTaxItemCategory;

        /* Examples of rate calculation:

                Fixed Rate based line items:
                Let Total Addresses:    12
                    Line Item Quantity: 1
                    Line Item Rate:     $150.00
                    Line Item Price:    $150.00

                Fixed rate line items must convert extended amount into pro rata rate:

               3 CSV Batches:
                        Fixed Rate            - Batch 1: ((7 / 12) * $150) / 7) = $12.50
                        Fixed Extended Amount - Batch 1: ((7 / 12) * $150))     =           $87.50
                        Fixed Rate            - Batch 2: ((3 / 12) * $150) / 3) = $12.50
                        Fixed Extended Amount - Batch 2: ((3 / 12) * $150))     =           $37.50
                        Fixed Rate            - Batch 3: ((2 / 12) * $150) / 2) = $12.50
                        Fixed Extended Amount - Batch 2: ((2 / 12) * $150))     =           $25.00
                        --------------------------------------------------------------------------
                                                                                           $150.00
                Unit based line items:
                Let Total Addresses:    12
                    Line Item Quantity: 1
                    Line Item Rate:     $12.50
                    Line Item Price:    $150.00

                    ** COULD Just use ili.Rate ?

                3 CSV Batches:
                        Unit Rate             - Batch 1: (12.50)                = $12.50
                        Unit Extended Amount  - Batch 1: ((7) * $12.50))        =           $87.50
                        Unit Rate             - Batch 2: (12.50)                = $12.50
                        Unit Extended Amount  - Batch 2: ((3) * $12.50))        =           $37.50
                        Unit Rate             - Batch 3: (12.50)                = $12.50
                        Unit Extended Amount  - Batch 2: ((2) * $12.50))        =           $25.00
                        --------------------------------------------------------------------------
                                                                                           $150.00

                Tiered based calculated rate line items:
                Let Total Addresses:    14
                    Line Item Quantity: 14
                    Line Item Rate:     $6.03
                    Line Item Price:    $6.03

                7 - 7 page doc  @ 0.41 - TN
                6 - 13 page doc @ 0.45 - MN
                1 - 18 page doc @ 0.46 - MN

                WRONG:
                3 CSV Batches:
                        Unit Rate             - Batch 1: ((7 / 14) * $6.03) / 7)   = $0.4307142857142857
                        Unit Extended Amount  - Batch 1: ((7 / 14) * $6.03))        =       $3.015
                        Unit Rate             - Batch 2: ((6 / 14) * $6.03) / 6)    = $0.4307142857142857
                        Unit Extended Amount  - Batch 2: ((6 / 14) * $6.03))        =       $2.5842857142857141
                        Unit Rate             - Batch 3: ((1 / 14) * $6.03) / 1)    = $0.4307142857142857
                        Unit Extended Amount  - Batch 2: ((1 / 14) * $6.03))        =       $0.4307142857142857
                        --------------------------------------------------------------------------
                                                                                            $6.03
                Using the rate per line item batch

                CORRECT:
                3 CSV Batches:
                        Unit Rate             - Batch 1: (0.41)                     = $0.41
                        Unit Extended Amount  - Batch 1: (7 * 0.41)                 =       $2.87
                        Unit Rate             - Batch 2: (0.45)                     = $0.45
                        Unit Extended Amount  - Batch 2: (6 * 0.45)                 =       $2.70
                        Unit Rate             - Batch 3: (0.46)                     = $0.46
                        Unit Extended Amount  - Batch 2: (1 * 0.46)                 =       $0.46
                        --------------------------------------------------------------------------
                                                                                            $6.03

             */

        ;WITH RateDistribution ( SalesTaxBatchKey
                                ,City
                                ,StateRegion
                                ,PostalCode
                                ,Quantity
                                ,LineNumber
                                ,LinesPerBatch
                                ,ProRataRate
                                ,LineItemPrice
                                ,UnitPrice
                                ,RateTypeKey
                                ,DestinationCode
                                ,IsSalesTaxExportable )
        AS
        (
            SELECT
                 stb.SalesTaxBatchKey
                ,btdp.City
                ,btdp.StateRegion
                ,btdp.PostalCode
                ,SUM(CAST(btdp.Quantity AS BIGINT)) as Quantity
                ,ROW_NUMBER() OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey ORDER BY btdp.PostalCode) AS LineNumber
                ,COUNT(*) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey) AS LinesPerBatch
                ,ROUND(CONVERT(NUMERIC(25, 10), ili.ExtendedAmount) / SUM(SUM(CAST(btdp.Quantity AS BIGINT))) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey), 8) AS ProRataRate
                ,CONVERT(NUMERIC(25, 3), ili.ExtendedAmount) AS LineItemPrice
                ,ISNULL(clirm.Price, 0) AS UnitPrice
                ,clir.RateTypeKey
                ,btdp.DestinationCode
                ,li.IsSalesTaxExportable
            FROM LASS.dbo.LASS_invoices i
                INNER JOIN LASS.dbo.LASS_InvoiceGenerationSessions igs ON igs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
                INNER JOIN LASS.dbo.LASS_InvoiceLineItems ili ON ili.InvoiceKey = i.InvoiceKey
                INNER JOIN LASS.dbo.LASS_SalesTaxBatch stb ON stb.InvoiceLineItemKey = ili.InvoiceLineItemKey
                INNER JOIN LASS.dbo.LASS_LineItems li ON li.LineItemKey = ili.LineItemKey
                INNER JOIN LASS.dbo.LASS_SalesTaxCodes stc ON stc.SalesTaxCodeKey = li.SalesTaxCodeKey
                INNER JOIN LASS.dbo.LASS_InvoiceLineItemBillingActivities iliba ON iliba.InvoiceLineItemKey = ili.InvoiceLineItemKey AND iliba.IncludeInSalesTaxBatch = 1
                INNER JOIN LASS.dbo.LASS_ClientLineItemRateModels clirm ON clirm.ClientLineItemRateModelKey = iliba.ClientLineItemRateModelKey
                INNER JOIN LASS.dbo.LASS_ClientLineItemRates clir ON clir.ClientLineItemRateKey = iliba.ClientLineItemRateKey
                INNER JOIN LASS.dbo.LASS_BillingActivityBatchCategoryDetails AS babcd ON iliba.BillingActivityBatchCategoryKey = babcd.BillingActivityBatchCategoryKey
                INNER JOIN LASS.dbo.tblBillingTransactionDeliveryPoints btdp ON btdp.BillingTransactionGuid = babcd.BillingTransactionGuid AND btdp.IsActive = 1
            WHERE li.UseCustomerTaxAddress = 0
              AND igs.InvoiceGenerationSessionId = @InvoiceGenerationSessionId
            GROUP BY stb.SalesTaxBatchKey,
                        btdp.City,
                        btdp.StateRegion,
                        btdp.PostalCode,
                        clir.RateTypeKey,
                        ili.ExtendedAmount,
                        clirm.Price,
                        clir.RateTypeKey,
                        btdp.DestinationCode,
                        li.IsSalesTaxExportable
        )
        -- Print / Postage based delivery point batches
        INSERT INTO LASS.dbo.LASS_SalesTaxBatchDetails
        (
            SalesTaxBatchDetailId,
            SalesTaxBatchKey,
            Quantity,
            Rate,
            City,
            Region,
            Zip,
            IsForeign,
            ShouldExport,
            UserAdded,
            DateAdded,
            IsActive
        )
        SELECT
             NEWID()
            ,rd.SalesTaxBatchKey
            ,rd.Quantity
           ,CASE
                -- Not a fixed rate - use Qty * Rate
                WHEN rd.RateTypeKey NOT IN (6, 8) THEN rd.UnitPrice
                -- Fixed rate, and last zip code.  Distribute the remainder to the last zip code.
                WHEN rd.LineNumber = rd.LinesPerBatch THEN ROUND(LineItemPrice - ISNULL((SELECT SUM(ROUND(ProRataRate, 3) * CAST(Quantity AS BIGINT))
                                                                                        FROM RateDistribution
                                                                                        WHERE LineItemPrice = rd.LineItemPrice
                                                                                                AND SalesTaxBatchKey = rd.SalesTaxBatchKey
                                                                                                AND LineNumber < LinesPerBatch)
                                                                                            , 0), 3) / CAST(rd.Quantity AS BIGINT)
                ELSE ROUND(rd.ProRataRate, 3)
             END
            ,rd.City
            ,rd.StateRegion
            ,rd.PostalCode
            ,IIF(rd.DestinationCode = 'D', 0, 1)                        -- If the destination code is not Domestic (F), consider the batch foreign. Including: Foreign (F), and near-foreign (N).
            ,IIF(rd.DestinationCode = 'D', rd.IsSalesTaxExportable, 0)  -- If batch is domestic then it should be exported, unless the line item is not exportable.  Foreign should not be exported.
            ,@UserName
            ,GETDATE()
            ,@IsActive
        FROM RateDistribution AS rd

        -- Update the details with the customer's taxable address for any detail that has a blank address.
        UPDATE stbd
            SET stbd.City = cc.TaxableCity,
                stbd.Region = cc.TaxableState,
                stbd.Zip = cc.TaxablePostalCode
        FROM LASS.dbo.LASS_SalesTaxBatchDetails stbd
            INNER JOIN LASS.dbo.LASS_SalesTaxBatch stb ON stb.SalesTaxBatchKey = stbd.SalesTaxBatchKey
            INNER JOIN LASS.dbo.LASS_InvoiceLineItems ili ON ili.InvoiceLineItemKey = stb.InvoiceLineItemKey
            INNER JOIN LASS.dbo.LASS_invoices i ON i.InvoiceKey = ili.InvoiceKey
            INNER JOIN LASS.dbo.LASS_InvoiceGenerationSessions igs ON igs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
            INNER JOIN LASS.dbo.LASS_ClientConfigurations cc ON cc.ClientConfigurationKey = i.ClientConfigurationKey
        WHERE igs.InvoiceGenerationSessionId = @InvoiceGenerationSessionId
            AND NULLIF(stbd.City, '') IS NULL
            AND NULLIF(stbd.Region, '') IS NULL
            AND NULLIF(stbd.Zip, '') IS NULL

        -- Service Item batches
        INSERT INTO LASS.dbo.LASS_SalesTaxBatchDetails
        (
            SalesTaxBatchDetailId,
            SalesTaxBatchKey,
            Quantity,
            Rate,
            City,
            Region,
            Zip,
            IsForeign,
            ShouldExport,
            UserAdded,
            DateAdded,
            IsActive
        )
        SELECT
            NEWID(),
            stb.SalesTaxBatchKey,
            SUM(ili.Quantity),
            ISNULL(ili.Rate, 0),
            cc.TaxableCity,
            cc.TaxableState,
            cc.TaxablePostalCode,
            0, -- Not Foreign
            li.IsSalesTaxExportable,
            @UserName,
            GETDATE(),
            @IsActive
        FROM LASS.dbo.LASS_invoices i
            INNER JOIN LASS.dbo.LASS_InvoiceGenerationSessions igs ON igs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
            INNER JOIN LASS.dbo.LASS_InvoiceLineItems ili ON ili.InvoiceKey = i.InvoiceKey
            INNER JOIN LASS.dbo.LASS_SalesTaxBatch stb ON stb.InvoiceLineItemKey = ili.InvoiceLineItemKey
            INNER JOIN LASS.dbo.LASS_LineItems li ON li.LineItemKey = ili.LineItemKey
            INNER JOIN LASS.dbo.LASS_SalesTaxCodes stc ON stc.SalesTaxCodeKey = li.SalesTaxCodeKey
            INNER JOIN LASS.dbo.LASS_ClientConfigurations cc ON cc.ClientConfigurationKey = i.ClientConfigurationKey
        WHERE igs.InvoiceGenerationSessionId = @InvoiceGenerationSessionId
        and li.UseCustomerTaxAddress = 1
        GROUP BY stb.SalesTaxBatchKey,
                 cc.TaxableCity,
                 cc.TaxableState,
                 cc.TaxablePostalCode,
                 li.IsSalesTaxExportable,
                 ili.Rate,
                 ili.ExtendedAmount

        END TRY
    BEGIN CATCH

        PRINT 'Error: ' + ERROR_MESSAGE()

        ROLLBACK TRAN LASS_SalesTaxBatch_Populate

        SET @ReturnCode=-102
        SET @ReturnMsg='Error creating LASS_SalesTaxBatch.  ERROR Code - ' + CAST(ISNULL(ERROR_NUMBER(),'') AS nvarchar(20)) + '  ERROR MESSAGE - ' + ERROR_MESSAGE()

        GOTO ERRORHANDLER

    END CATCH

    -- Everything succeeded so commit
    COMMIT TRAN LASS_SalesTaxBatch_Populate

    SET @ReturnCode = 1
    SET @ReturnMsg = 'Success'

    RETURN

    ERRORHANDLER:
        RETURN
END
GO
