USE LASS
Go

SELECT * from LASS_InvoiceTypes

-- lis
select top 1 * from LASS_BillingActivityBatch where UserAdded = 'Billing_Activity_Batch_Process' and IsMaestroBatch = 0

select top 1 * from LASS_BillingActivityBatch where UserAdded = 'llservice@letterlogic.com' and IsMaestroBatch = 0
