USE [LASS]
GO

DROP PROCEDURE [dbo].[LASS_GenerateBillingTransactionData_LIS_LADS]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[LASS_GenerateBillingTransactionData_LIS_LADS]
(
    @InvoiceGenerationSessionId     UNIQUEIDENTIFIER = NULL
)
/*=========================================================
NAME:             [dbo].[LASS_GenerateBillingTransactionData_LIS_LADS]
DESCRIPTION:      Generates billing transaction data for LIS and LADS platforms or
                    more specifically, invoice line items where billing activities are
                    directly batched outside of maestro (no billing transaction data exists).

MODIFICATIONS:
  AUTHOR        date        DESC
  dflanigan     20240310    initial version
=========================================================

=========================================================
*/
AS

BEGIN
    SET NOCOUNT ON

    -- Get invoice generation session key
    DECLARE @InvoiceGenerationSessionKey BIGINT = (
        SELECT TOP 1 ligs.InvoiceGenerationSessionKey
        FROM dbo.LASS_InvoiceGenerationSessions ligs
        WHERE ligs.InvoiceGenerationSessionId = @InvoiceGenerationSessionId)

    -- Remove Temporary Tables
    IF OBJECT_ID('tempdb..#NonServiceInvoiceLineItems') IS NOT NULL
    BEGIN
        DROP TABLE #NonServiceInvoiceLineItems
    END

    -- Create Temporary Tables
    -- Table: Non-Service Invoice Line Items
    CREATE TABLE #NonServiceInvoiceLineItems
    (
        [InvoiceLineItemKey] [bigint] NULL,
        [InvoiceLineItemGroupKey] [nvarchar](128) NULL,
        [LineItemKey] [bigint] NULL,
        [TaxCode] [nvarchar](15) NULL,
        [TaxCategory] [nvarchar](15) NULL
    )

    -- Insert Non-Service Invoice Line Items
    INSERT INTO #NonServiceInvoiceLineItems
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
    FROM LASS_InvoiceGenerationSessions ligs
        -- Join invoices generation session to invoices
        INNER JOIN LASS_Invoices i
            ON ligs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
        -- Gets invoice line items
        INNER JOIN LASS_InvoiceLineItems lili
            ON lili.InvoiceKey = i.InvoiceKey
        -- Get lass line items
        INNER JOIN LASS_LineItems lli
            ON lli.LineItemKey = lili.LineItemKey
        -- Get invoice line item billing activities
        INNER JOIN LASS_InvoiceLineItemBillingActivities liliba
            ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
               AND liliba.IncludeInSalesTaxBatch = 1 -- Include as ST
        -- Join Sales Tax Codes
        INNER JOIN LASS_SalesTaxCodes lstc
            ON lstc.SalesTaxCodeKey = lli.SalesTaxCodeKey
    WHERE ligs.InvoiceGenerationSessionKey = @InvoiceGenerationSessionKey                   -- Filter by session
    AND lli.UseCustomerTaxAddress = 0                                                       -- Exclude service lines (Generated later)
    AND NOT (EXISTS(                                                                        -- Exclude lines with btdp data
            SELECT * FROM LASS_BillingActivityBatchCategoryDetails lbabcd2
                INNER JOIN tblBillingTransactionDeliveryPoints btdp
                    ON btdp.BillingTransactionGuid = lbabcd2.BillingTransactionGuid AND btdp.IsActive = 1
            WHERE lbabcd2.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey))
    GROUP BY lili.InvoiceLineItemKey,
             lili.InvoiceLineItemGroupKey,
             lili.LineItemKey,
             lstc.TaxCode,
             lli.SalesTaxItemCategory

    -- For each non-service invoice line item, generate billing transaction data based on calulator module
    DECLARE @TotalInvoiceLineItemRows INT = (SELECT COUNT(*) FROM #NonServiceInvoiceLineItems)
    DECLARE @CurrentInvoiceLineItemRow INT = 1

    -- Loop through each InvoiceLineItemKey
    WHILE @CurrentInvoiceLineItemRow <= @TotalInvoiceLineItemRows
    BEGIN
        -- Get the InvoiceLineItemKey for the current row
        DECLARE @InvoiceLineItemKey BIGINT = (
            SELECT InvoiceLineItemKey
        FROM (
            SELECT InvoiceLineItemKey, ROW_NUMBER() OVER (ORDER BY (InvoiceLineItemKey)) AS RowNum
            FROM #NonServiceInvoiceLineItems) AS T
        WHERE RowNum = @CurrentInvoiceLineItemRow)

        -- Get the LineItemKey for the current row
        DECLARE @LineItemKey BIGINT = (
            SELECT LineItemKey
        FROM (
            SELECT LineItemKey, ROW_NUMBER() OVER (ORDER BY (InvoiceLineItemKey)) AS RowNum
            FROM #NonServiceInvoiceLineItems) AS T
        WHERE RowNum = @CurrentInvoiceLineItemRow)

        -- Get the LineItemCalculatorModule for the current InvoiceLineItemKey
        DECLARE @LineItemCalculatorModule NVARCHAR(128) = (
            SELECT li.LineItemCalculatorModule
                FROM LASS_InvoiceLineItems lili
            INNER JOIN LASS_LineItems li
                ON lili.LineItemKey = li.LineItemKey
        WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey)

        -- Oddly enough, we don't actually store any information about which host system the billing activity batch
        -- data came from. Our best chance of identifying this is to infer it from the data stream details of the
        -- billing activity batch category (see below). Alternatively, you could maybe assume this given the
        -- 'UserAdded' column for the batch as it appears to be unique for LIS/LADS. But, in any case, here we are :)

        -- Determine host system
        DECLARE @HostSystemDataStreamDetailId UNIQUEIDENTIFIER = (
        SELECT TOP 1
            lbabcd.DataStreamDetailId -- all billing activity batch category details are from a single source system
        FROM LASS_InvoiceLineItemBillingActivities liliba
            INNER JOIN LASS_BillingActivityBatchCategories lbabc
                ON liliba.BillingActivityBatchCategoryKey = lbabc.BillingActivityBatchCategoryKey
            INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd
                ON lbabc.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
        WHERE liliba.InvoiceLineItemKey = @InvoiceLineItemKey)

        DECLARE @HostSystemId INT = 0;  -- Unknown / NotSet

        IF @HostSystemId = 0 AND EXISTS ( SELECT * FROM LetterShop.dbo.LIS_DataStreamDetails WHERE DataStreamDetailId = @HostSystemDataStreamDetailId)
        BEGIN
            SET @HostSystemId = 1       -- LIS
        END

        IF @HostSystemId = 0 AND EXISTS ( SELECT * FROM LADS.dbo.LADS_DataStreamDetails WHERE DataStreamDetailId = @HostSystemDataStreamDetailId)
        BEGIN
            SET @HostSystemId = 2       -- LADS
        END

        -- For any invoice line item where billing activity batch category details appear to be generated from a non-Maestro
        -- system, we will attempt to populate the billing transactions table and billing transaction delivery points.
        IF (@HostSystemId != 0)
        BEGIN
            -- Attempt to populate the billing transactions table and billing transaction delivery points for the current InvoiceLineItemKey
            EXEC LASS_GenerateBillingTransactionDeliveryPointData_LIS_LADS @InvoiceGenerationSessionKey, @InvoiceLineItemKey, @LineItemKey, @LineItemCalculatorModule, @HostSystemId
        END

        -- Increment the counter
        SET @CurrentInvoiceLineItemRow = @CurrentInvoiceLineItemRow + 1
    END
END

GO