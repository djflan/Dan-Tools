CREATE TABLE [dbo].[LASS_InvoiceGenerationSessionLineItemDetails] (
    [InvoiceGenerationSessionLineItemDetailId] BIGINT           NOT NULL,
    [InvoiceGenerationSessionKey]              BIGINT           NOT NULL,
    [InvoiceLineItemKey]                       BIGINT           NOT NULL,
    [LineItemKey]                              BIGINT           NOT NULL,
    [HostSystemId]                             INT              CONSTRAINT [DEFAULT_LASS_InvoiceGenerationSessionLineItemDetails_HostSystemId] DEFAULT 0 NOT NULL,
    [BillingTransactionGuid]                   UNIQUEIDENTIFIER NULL,
    CONSTRAINT [PK_LASS_InvoiceGenerationSessionLineItemDetails] PRIMARY KEY CLUSTERED ([InvoiceGenerationSessionLineItemDetailId] ASC),
    CONSTRAINT [FK_LASS_InvoiceGenerationSessionLineItemDetails_LASS_InvoiceGenerationSessions] FOREIGN KEY ([InvoiceGenerationSessionKey]) REFERENCES [dbo].[LASS_InvoiceGenerationSessions] ([InvoiceGenerationSessionKey]),
    CONSTRAINT [FK_LASS_InvoiceGenerationSessionLineItemDetails_LASS_InvoiceLineItems] FOREIGN KEY ([InvoiceLineItemKey]) REFERENCES [dbo].[LASS_InvoiceLineItems] ([InvoiceLineItemKey]),
    CONSTRAINT [FK_LASS_InvoiceGenerationSessionLineItemDetails_LASS_LineItems] FOREIGN KEY ([LineItemKey]) REFERENCES [dbo].[LASS_LineItems] ([LineItemKey])
);