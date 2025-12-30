use lass
go

--select * from LASS_InvoiceGenerationSessions where InvoiceGenerationSessionKey = 141475

;WITH RateDistributionB ( SalesTaxBatchKey
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
                ,SUM(btdp.Quantity) AS Quantity
				,ROW_NUMBER() OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey ORDER BY btdp.PostalCode) AS LineNumber
				,COUNT(*) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey) AS LinesPerBatch
                ,ROUND(CONVERT(NUMERIC(25, 10), ili.ExtendedAmount) / SUM(SUM(btdp.Quantity)) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey), 8) AS ProRataRate
				,CONVERT(NUMERIC(25, 3), ili.ExtendedAmount) AS LineItemPrice
				,ISNULL(clirm.Price, 0) AS UnitPrice		
				,clir.RateTypeKey
				,btdp.DestinationCode		
				,li.IsSalesTaxExportable	
			FROM LASS.dbo.LASS_invoices i
				INNER JOIN LASS.dbo.LASS_InvoiceGenerationSessions igs (NOLOCK) ON igs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
				INNER JOIN LASS.dbo.LASS_InvoiceLineItems ili (NOLOCK) ON ili.InvoiceKey = i.InvoiceKey
				INNER JOIN LASS.dbo.LASS_SalesTaxBatch stb (NOLOCK) ON stb.InvoiceLineItemKey = ili.InvoiceLineItemKey			
				INNER JOIN LASS.dbo.LASS_LineItems li (NOLOCK) ON li.LineItemKey = ili.LineItemKey
				INNER JOIN LASS.dbo.LASS_SalesTaxCodes stc (NOLOCK) ON stc.SalesTaxCodeKey = li.SalesTaxCodeKey
				INNER JOIN LASS.dbo.LASS_InvoiceLineItemBillingActivities iliba (NOLOCK) ON iliba.InvoiceLineItemKey = ili.InvoiceLineItemKey AND iliba.IncludeInSalesTaxBatch = 1	
				INNER JOIN LASS.dbo.LASS_ClientLineItemRateModels clirm (NOLOCK) ON clirm.ClientLineItemRateModelKey = iliba.ClientLineItemRateModelKey		
				INNER JOIN LASS.dbo.LASS_ClientLineItemRates clir (NOLOCK) ON clir.ClientLineItemRateKey = iliba.ClientLineItemRateKey
				--INNER JOIN LASS.dbo.LASS_BillingActivityBatchCategoryDetails AS babcd ON iliba.BillingActivityBatchCategoryKey = babcd.BillingActivityBatchCategoryKey
                INNER JOIN LASS.dbo.LASS_TaxableInvoiceLineItems tili (NOLOCK) ON tili.InvoiceLineItemKey = ili.InvoiceLineItemKey AND tili.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
                INNER JOIN LASS.dbo.tblBillingTransactionDeliveryPoints btdp (NOLOCK) ON btdp.BillingTransactionGuid = tili.GeneratedBillingTransactionGuid AND btdp.IsActive = 1
			WHERE li.UseCustomerTaxAddress = 0
			  AND igs.InvoiceGenerationSessionId = '373d3a02-43c5-4226-bc80-6e9b61a551a6'
              AND (tili.HostSystemId = 1 OR tili.HostSystemId = 2) -- Only LL Batches
              AND tili.Ignore = 0                                                                 -- Only Non-ignored line items
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
		) select * from RateDistributionB