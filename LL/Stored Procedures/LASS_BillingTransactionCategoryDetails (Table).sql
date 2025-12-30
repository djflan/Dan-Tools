CREATE TABLE [dbo].[LASS_BillingTransactionCategoryDetails] (
    [BillingTransactionCategoryDetailId]    BIGINT           NOT NULL,
    [BillingTransactionGuid]                UNIQUEIDENTIFIER NOT NULL,
    [InvoiceGenerationSessionKey]           BIGINT           NOT NULL,
    [InvoiceLineItemKey]                    BIGINT           NOT NULL,
    [LineItemKey]                           BIGINT           NOT NULL,
    [LineItemCalculatorModule]              NVARCHAR (256)   NULL,
    [HostSystemId]                          INT              CONSTRAINT [DEFAULT_LASS_BillingTransactionCategoryDetails_HostSystemId] DEFAULT 0 NOT NULL,
    [BillingActivityBatchCategoryDetailKey] BIGINT           NOT NULL,
    CONSTRAINT [PK_LASS_BillingTransactionCategoryDetails] PRIMARY KEY CLUSTERED ([BillingTransactionCategoryDetailId] ASC),
    CONSTRAINT [FK_LASS_BillingTransactionCategoryDetails_LASS_BillingActivityBatchCategoryDetails] FOREIGN KEY ([BillingActivityBatchCategoryDetailKey]) REFERENCES [dbo].[LASS_BillingActivityBatchCategoryDetails] ([BillingActivityBatchCategoryDetailKey]),
    CONSTRAINT [FK_LASS_BillingTransactionCategoryDetails_LASS_InvoiceGenerationSessions] FOREIGN KEY ([InvoiceGenerationSessionKey]) REFERENCES [dbo].[LASS_InvoiceGenerationSessions] ([InvoiceGenerationSessionKey]),
    CONSTRAINT [FK_LASS_BillingTransactionCategoryDetails_LASS_InvoiceLineItems] FOREIGN KEY ([InvoiceLineItemKey]) REFERENCES [dbo].[LASS_InvoiceLineItems] ([InvoiceLineItemKey]),
    CONSTRAINT [FK_LASS_BillingTransactionCategoryDetails_LASS_LineItems] FOREIGN KEY ([LineItemKey]) REFERENCES [dbo].[LASS_LineItems] ([LineItemKey])
);

