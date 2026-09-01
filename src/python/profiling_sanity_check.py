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
count_divergences = divergences[divergences['difference'] != 0].shape[0]

print(f"  Quantidade de divergências: {count_divergences}. Representa {count_divergences / total_records * 100:.2f} % do total de registros.")

divergences['diff_rounded'] = divergences['difference'].round(2)
divergences_reais = divergences[divergences['diff_rounded'].abs() > 0.05]
print(f"  Quantidade de divergências: {divergences_reais.shape[0]}. Representa {divergences_reais.shape[0] / total_records * 100:.2f} % do total de registros.")