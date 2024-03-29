USE LASS
GO

DECLARE @InvoiceLineItemKey BIGINT = 3111643


-- LL.Components.LASS.LineItemCalculators.ReturnLogic.ReturnLogicReturnsLineItemCalculator
SELECT SUM(CAST(lrrr.IsReturnedCode AS INT)) as NumLisReturns
FROM LASS_InvoiceLineItems (NOLOCK) lili
    INNER JOIN LASS_InvoiceLineItemBillingActivities liliba (NOLOCK)
        ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
    INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd (NOLOCK)
        ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
        AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
    INNER JOIN LetterShop.dbo.LIS_ReturnLogicDetails lrd (NOLOCK)
        ON lrd.ReturnLogicDetailId = lbabcd.ReturnLogicDetailId
    INNER JOIN LetterShop.dbo.LIS_ReturnLogicReturnReasons lrrr (NOLOCK)
        ON lrrr.ReturnLogicReturnReasonId = lrd.ReturnLogicReturnReasonId
WHERE lili.InvoiceLineItemKey = 3111642--@InvoiceLineItemKey


-- LL.Components.LASS.LineItemCalculators.ReturnLogic.ReturnLogicUpdatesLineItemCalculator
SELECT SUM(CAST(lrrr.IsUpdatedCode AS INT)) as NumLisUpdates
FROM LASS_InvoiceLineItems (NOLOCK) lili
    INNER JOIN LASS_InvoiceLineItemBillingActivities liliba (NOLOCK)
        ON lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
    INNER JOIN LASS_BillingActivityBatchCategoryDetails lbabcd (NOLOCK)
        ON liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
        AND liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
    INNER JOIN LetterShop.dbo.LIS_ReturnLogicDetails lrd (NOLOCK)
        ON lrd.ReturnLogicDetailId = lbabcd.ReturnLogicDetailId
    INNER JOIN LetterShop.dbo.LIS_ReturnLogicReturnReasons lrrr (NOLOCK)
        ON lrrr.ReturnLogicReturnReasonId = lrd.ReturnLogicReturnReasonId
WHERE lili.InvoiceLineItemKey = @InvoiceLineItemKey