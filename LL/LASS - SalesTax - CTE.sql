USE LASS
GO

DECLARE @InvoiceGenerationSessionId UNIQUEIDENTIFIER = (SELECT TOP 1 i.InvoiceGenerationSessionId FROM LASS_InvoiceGenerationSessions i WHERE i.InvoiceGenerationSessionKey = 137927)
DECLARE @SalesTaxBatchKey BIGINT = 959163

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
				,SUM(btdp.Quantity) as Quantity
				,ROW_NUMBER() OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey ORDER BY btdp.PostalCode) AS LineNumber
				,COUNT(*) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey) AS LinesPerBatch
				,ROUND(CONVERT(NUMERIC(25, 10), ili.ExtendedAmount) / SUM(SUM(btdp.Quantity)) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey), 8) AS ProRataRate
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
              AND SalesTaxBatchKey = @SalesTaxBatchKey
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

        SELECT * FROM RateDistribution