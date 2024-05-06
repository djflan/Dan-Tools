USE LASS 
GO

DECLARE @InvoiceGenerationSessionId UNIQUEIDENTIFIER = (SELECT TOP 1 InvoiceGenerationSessionId FROM LASS_InvoiceGenerationSessions WHERE InvoiceGenerationSessionKey = 136083)

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
			FROM LASS.dbo.LASS_invoices i (NOLOCK)
				INNER JOIN LASS.dbo.LASS_InvoiceGenerationSessions igs (NOLOCK) ON igs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
				INNER JOIN LASS.dbo.LASS_InvoiceLineItems ili (NOLOCK) ON ili.InvoiceKey = i.InvoiceKey
				INNER JOIN LASS.dbo.LASS_SalesTaxBatch stb (NOLOCK) ON stb.InvoiceLineItemKey = ili.InvoiceLineItemKey			
				INNER JOIN LASS.dbo.LASS_LineItems li (NOLOCK) ON li.LineItemKey = ili.LineItemKey
				INNER JOIN LASS.dbo.LASS_SalesTaxCodes stc (NOLOCK) ON stc.SalesTaxCodeKey = li.SalesTaxCodeKey
				INNER JOIN LASS.dbo.LASS_InvoiceLineItemBillingActivities iliba (NOLOCK) ON iliba.InvoiceLineItemKey = ili.InvoiceLineItemKey AND iliba.IncludeInSalesTaxBatch = 1	
				INNER JOIN LASS.dbo.LASS_ClientLineItemRateModels clirm (NOLOCK) ON clirm.ClientLineItemRateModelKey = iliba.ClientLineItemRateModelKey		
				INNER JOIN LASS.dbo.LASS_ClientLineItemRates clir (NOLOCK) ON clir.ClientLineItemRateKey = iliba.ClientLineItemRateKey
				INNER JOIN LASS.dbo.LASS_BillingActivityBatchCategoryDetails AS babcd (NOLOCK) ON iliba.BillingActivityBatchCategoryKey = babcd.BillingActivityBatchCategoryKey
                -- *** I Believe the below join is the issue. We haven't updated the billing transaction delivery point guid on babcd. ***
				INNER JOIN LASS.dbo.tblBillingTransactionDeliveryPoints btdp (NOLOCK) ON btdp.BillingTransactionGuid = babcd.BillingTransactionGuid AND btdp.IsActive = 1
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
		-- SELECT
		-- (
		-- 	SalesTaxBatchDetailId, 
		-- 	SalesTaxBatchKey, 
		-- 	Quantity, 
		-- 	Rate,
		-- 	City, 
		-- 	Region, 
		-- 	Zip, 
		-- 	IsForeign, 
		-- 	ShouldExport, 
		-- 	UserAdded, 
		-- 	DateAdded, 
		-- 	IsActive								
		-- )

		SELECT
			 NEWID() as SalesTaxBatchDetailId
			,rd.SalesTaxBatchKey as SalesTaxBatchKey
			,rd.Quantity as Quantity
		   ,CASE
				-- Not a fixed rate - use Qty * Rate
				WHEN rd.RateTypeKey NOT IN (6, 8) THEN rd.UnitPrice
				-- Fixed rate, and last zip code.  Distribute the remainder to the last zip code.
   				WHEN rd.LineNumber = rd.LinesPerBatch THEN ROUND(LineItemPrice - ISNULL((SELECT SUM(ROUND(ProRataRate, 3) * Quantity) 
																						FROM RateDistribution 
																						WHERE LineItemPrice = rd.LineItemPrice
																								AND SalesTaxBatchKey = rd.SalesTaxBatchKey
																								AND LineNumber < LinesPerBatch)
																							, 0), 3) / rd.Quantity
   				ELSE ROUND(rd.ProRataRate, 3)
			 END as Rate
			,rd.City as City
			,rd.StateRegion as Region
			,rd.PostalCode as Zip
			,IIF(rd.DestinationCode = 'D', 0, 1) as DestinationCode				-- If the destination code is not Domestic (F), consider the batch foreign. Including: Foreign (F), and near-foreign (N).
			,IIF(rd.DestinationCode = 'D', rd.IsSalesTaxExportable, 0) as Exportable	-- If batch is domestic then it should be exported, unless the line item is not exportable.  Foreign should not be exported.
			,'dflanigan - testing' as UserAdded
			,GETDATE() as Date
			,1 as IsActive
		FROM RateDistribution AS rd (NOLOCK)