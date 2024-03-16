use lass
go

DECLARE @invoiceLineItemKey BIGINT = 3106258

select lbabcd.* from LASS_InvoiceLineItems (NOLOCK) lili 
    inner join LASS_InvoiceLineItemBillingActivities (NOLOCK) liliba 
        on lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
    inner join LASS_BillingActivityBatchCategoryDetails (NOLOCK) lbabcd 
        on liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
        and liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
where lili.InvoiceLineItemKey = @invoiceLineItemKey

select * from tblBillingTransactions (NOLOCK)
where BillingTransactionGuid in 
(
    select distinct lbabcd.BillingTransactionGuid from LASS_InvoiceLineItems (NOLOCK) lili 
    inner join LASS_InvoiceLineItemBillingActivities (NOLOCK) liliba 
        on lili.InvoiceLineItemKey = liliba.InvoiceLineItemKey
    inner join LASS_BillingActivityBatchCategoryDetails (NOLOCK) lbabcd 
        on liliba.BillingActivityBatchCategoryKey = liliba.BillingActivityBatchCategoryKey
        and liliba.BillingActivityBatchCategoryKey = lbabcd.BillingActivityBatchCategoryKey
where lili.InvoiceLineItemKey = @invoiceLineItemKey)

--select * from tblBillingTransactionDeliveryPoints WHEre BillingTransactionId = 88860144