import pandas as pd
import numpy as np
from pathlib import Path

dir_dataset = Path(__file__).parent.parent.parent / "dataset"


print("Qual a quantidade total de registros, quantos customer_id únicos e quantos customer_unique_id únicos existem? Qual o cliente com maior número de pedidos?")

df_customers = pd.read_csv(dir_dataset / "olist_customers_dataset.csv") 

total_records = len(df_customers)

print(f"Quantidade total de registros: {total_records}")
print(f"Quantidade de customer_id únicos: {df_customers['customer_id'].nunique()}")
print(f"Quantidade de customer_unique_id únicos: {df_customers['customer_unique_id'].nunique()}")

customer_order_counts = df_customers.groupby('customer_unique_id').size()
max_orders_customer = customer_order_counts.idxmax()
print(f"Cliente com maior número de pedidos: {max_orders_customer} com {customer_order_counts.max()} pedidos")


print("\nEm olist_orders_dataset, quais colunas de data possuem nulos e quantos pedidos estão em cada order_status?")
print("\nColunas de data com nulos:")

df_orders = pd.read_csv(dir_dataset / "olist_orders_dataset.csv")

for col in df_orders.columns:
    if col in ['order_purchase_timestamp', 'order_approved_at', 'order_delivered_carrier_date', 'order_delivered_customer_date', 'order_estimated_delivery_date']:
        null_count = df_orders[col].isnull().sum()
        if null_count > 0:
            print(f"  {col}: {null_count} nulos")

order_status_counts = df_orders['order_status'].value_counts()
print("\nQuantidade de pedidos em cada order_status:")
count_delivered = 0
for status, count in order_status_counts.items():
    print(f"  {status}: {count}")
    if status == 'delivered':
        count_delivered = count

print("\nExistem linhas onde order_delivered_customer_date < order_approved_at? Quantas?")
count = (df_orders['order_delivered_customer_date'] < df_orders['order_approved_at']).sum()
print(f"  Quantidade de linhas: {count}. Representa {count / total_records * 100:.2f} % do total de registros.")

print("\nQual a quantidade de pedidos que foram entregues com atraso (order_delivered_customer_date > order_estimated_delivery_date)?")
count = (df_orders['order_delivered_customer_date'] > df_orders['order_estimated_delivery_date']).sum()
print(f"  Quantidade de pedidos: {count}. Representa {count / count_delivered * 100:.2f} % do total de registros.")

print("\nAgrupando price + freight_value e comparando com payment_value por order_id, quantas divergências aparecem?")
df_order_items = pd.read_csv(dir_dataset / "olist_order_items_dataset.csv")
df_payments = pd.read_csv(dir_dataset / "olist_order_payments_dataset.csv")

df_order_items_grouped = df_order_items.groupby('order_id').agg({'price': 'sum', 'freight_value': 'sum'}).reset_index()
df_payments_grouped = df_payments.groupby('order_id').agg({'payment_value': 'sum'}).reset_index()

divergences = pd.merge(df_order_items_grouped, df_payments_grouped, on='order_id', how='inner')
divergences['difference'] = divergences['price'] + divergences['freight_value'] - divergences['payment_value']
# Quantidade de divergências (diferença diferente de 0) sem round. Utilizado para verificar se existem divergências significativas, considerando que pequenas diferenças podem ocorrer devido a arredondamentos ou taxas adicionais. Gerando números muito pequenos, como 1e-15, que não são relevantes para a análise. Por isso, é mais apropriado considerar apenas divergências significativas, arredondando a diferença para 2 casas decimais e filtrando aquelas com valor absoluto maior que 0.05.
# count_divergences = divergences[divergences['difference'] != 0].shape[0]

# print(f"  Quantidade de divergências: {count_divergences}. Representa {count_divergences / total_records * 100:.2f} % do total de registros.")

divergences['diff_rounded'] = divergences['difference'].round(2)
divergences_reais = divergences[divergences['diff_rounded'].abs() > 0.05]
print(f"  Quantidade de divergências: {divergences_reais.shape[0]}. Representa {divergences_reais.shape[0] / total_records * 100:.2f} % do total de registros.")

df_reviews = pd.read_csv(dir_dataset / "olist_order_reviews_dataset.csv")
print("\nQual a distribuição das notas (review_score de 1 a 5)?")
review_score_distribution = df_reviews['review_score'].value_counts().sort_index()
for score, count in review_score_distribution.items():
    print(f"  Nota {score}: {count}")

print("\nO review_id é 100% único ou existem duplicidades?")
review_id_unique = df_reviews['review_id'].is_unique
review_id_duplicates = df_reviews['review_id'].duplicated().sum()
print(f"  O review_id é único: {review_id_unique}. Quantidade de duplicidades: {review_id_duplicates}")

df_geolocation = pd.read_csv(dir_dataset / "olist_geolocation_dataset.csv")
print("\nO geolocation_zip_code_prefix é único? (Se tiver duplicidades de coordenadas para o mesmo CEP, como você planeja desduplicar isso no futuro para não explodir o modelo com cardinalidade muitos-para-muitos?).")

geolocation_zip_code_prefix_unique = df_geolocation['geolocation_zip_code_prefix'].is_unique
geolocation_zip_code_prefix_duplicates = df_geolocation['geolocation_zip_code_prefix'].duplicated().sum()
print(f"  O geolocation_zip_code_prefix é único: {geolocation_zip_code_prefix_unique}. Quantidade de duplicidades: {geolocation_zip_code_prefix_duplicates}")