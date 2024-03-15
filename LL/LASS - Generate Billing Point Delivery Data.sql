USE LASS
GO

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
    IsActive)
VALUES
    (NEWID(), 3111640, 1, 'NCOA', 17, 'SD020900', 'Service', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111641, 1, 'Postage', 20, 'FR020100', 'Postage', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111637, 1, 'Additional Pages', 13, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111643, 1, 'ReturnLogic', 29, 'SD020900', 'Service', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111636, 1, 'Lettershop', 31, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111638, 1, 'Inserts', 2, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111639, 1, 'Duplex Fee', 9, 'P0000000', 'Print', 'dflanigan', GETDATE(), 1),
    (NEWID(), 3111642, 1, 'ReturnLogic', 32, 'SD020900', 'Service', 'dflanigan', GETDATE(), 1)

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

    SELECT @LineItemCalculatorModule

    -- Increment the counter
    SET @CurrentInvoiceLineItemRow = @CurrentInvoiceLineItemRow + 1
END



